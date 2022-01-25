module Capability.Marlowe
  ( class ManageMarlowe
  , createWallet
  , restoreWallet
  , followContract
  , createPendingFollowerApp
  , followContractWithPendingFollowerApp
  , createContract
  , applyTransactionInput
  , redeem
  , getRoleContracts
  , getFollowerApps
  , subscribeToWallet
  , unsubscribeFromWallet
  , subscribeToPlutusApp
  , unsubscribeFromPlutusApp
  ) where

import Prologue

import API.Lenses
  ( _cicContract
  , _cicCurrentState
  , _cicDefinition
  , _observableState
  )
import API.Marlowe.Run.Wallet.CentralizedTestnet
  ( ClientServerErrorRow
  , CreateWalletError
  , RestoreWalletError
  , clientServerError
  )
import AppM (AppM)
import Bridge (toBack, toFront)
import Capability.MarloweStorage (class ManageMarloweStorage)
import Capability.MarloweStorage (class ManageMarloweStorage)
import Capability.PAB (class ManagePAB)
import Capability.PAB
  ( activateContract
  , getContractInstanceObservableState
  , getWalletContractInstances
  , invokeEndpoint
  ) as PAB
import Capability.PlutusApps.MarloweApp as MarloweApp
import Capability.Wallet (class ManageWallet)
import Capability.Wallet as Wallet
import Component.Contacts.Lenses
  ( _companionAppId
  , _marloweAppId
  , _pubKeyHash
  , _walletId
  , _walletInfo
  )
import Component.Contacts.Types (WalletDetails, WalletId, WalletInfo)
import Control.Monad.Except (ExceptT(..), except, lift, runExceptT, withExceptT)
import Control.Monad.Reader (asks)
import Data.Address (Address)
import Data.Argonaut.Decode (JsonDecodeError)
import Data.Argonaut.Extra (parseDecodeJson)
import Data.Array (filter, find) as Array
import Data.Bifunctor (lmap)
import Data.Lens (view)
import Data.Map (Map, fromFoldable)
import Data.Maybe (maybe')
import Data.MnemonicPhrase (MnemonicPhrase)
import Data.MnemonicPhrase as MP
import Data.MnemonicPhrase.Word (toString) as Word
import Data.Newtype (un, unwrap)
import Data.Passpharse (Passphrase)
import Data.Traversable (traverse)
import Data.Tuple.Nested ((/\))
import Data.Variant (Variant)
import Data.WalletNickname (WalletNickname)
import Data.WalletNickname as WN
import Env (Env(..))
import Halogen (HalogenM, liftAff)
import Marlowe.Client (ContractHistory)
import Marlowe.PAB (PlutusAppId, fromContractInstanceId)
import Marlowe.Semantics
  ( Contract
  , MarloweData
  , MarloweParams
  , TokenName
  , TransactionInput
  )
import MarloweContract (MarloweContract(..))
import Plutus.PAB.Webserver.Types
  ( CombinedWSStreamToServer(..)
  , ContractInstanceClientState
  )
import Plutus.V1.Ledger.Crypto (PubKeyHash(..)) as Back
import Types (AjaxResponse, DecodedAjaxResponse)
import Wallet.Emulator.Wallet (Wallet(..)) as Back
import WebSocket.Support as WS

-- The `ManageMarlowe` class provides a window on the `ManagePAB` and `ManageWallet`
-- capabilities with functions specific to Marlowe.
class
  ( ManagePAB m
  , ManageMarloweStorage m
  , ManageWallet m
  ) <=
  ManageMarlowe m where
  createWallet
    :: WalletNickname
    -> Passphrase
    -> m
         ( Either CreateWalletError
             { mnemonic :: MnemonicPhrase, walletDetails :: WalletDetails }
         )
  restoreWallet
    :: WalletNickname
    -> MnemonicPhrase
    -> Passphrase
    -> m (Either RestoreWalletError WalletDetails)
  followContract
    :: WalletDetails
    -> MarloweParams
    -> m (DecodedAjaxResponse (Tuple PlutusAppId ContractHistory))
  createPendingFollowerApp :: WalletDetails -> m (AjaxResponse PlutusAppId)
  followContractWithPendingFollowerApp
    :: WalletDetails
    -> MarloweParams
    -> PlutusAppId
    -> m (DecodedAjaxResponse (Tuple PlutusAppId ContractHistory))
  createContract
    :: WalletDetails
    -> Map TokenName Address
    -> Contract
    -> m (AjaxResponse Unit)
  applyTransactionInput
    :: WalletDetails
    -> MarloweParams
    -> TransactionInput
    -> m (AjaxResponse Unit)
  redeem :: WalletDetails -> MarloweParams -> TokenName -> m (AjaxResponse Unit)
  getRoleContracts
    :: WalletDetails -> m (DecodedAjaxResponse (Map MarloweParams MarloweData))
  getFollowerApps
    :: WalletDetails
    -> m (DecodedAjaxResponse (Map PlutusAppId ContractHistory))
  subscribeToPlutusApp :: PlutusAppId -> m Unit
  subscribeToWallet :: WalletId -> m Unit
  unsubscribeFromPlutusApp :: PlutusAppId -> m Unit
  unsubscribeFromWallet :: WalletId -> m Unit

fetchWalletDetails
  :: forall m r
   . ManageMarlowe m
  => WalletNickname
  -> WalletInfo
  -> ExceptT (Variant (ClientServerErrorRow r)) m WalletDetails
fetchWalletDetails walletNickname walletInfo = withExceptT clientServerError do
  let
    walletId = view _walletId walletInfo
  -- Get all plutus contracts associated with the restored wallet.
  plutusContracts <- ExceptT $ PAB.getWalletContractInstances walletId
  -- If we already have the plutus contract for the wallet companion and marlowe app
  -- let's use those, if note activate new instances of them
  { companionAppId, marloweAppId } <- ExceptT $
    activateOrRestorePlutusCompanionContracts walletId plutusContracts
  -- TODO (as part of SCP-3360):
  --   create a list of "loading contracts" with the plutusContracts of type MarloweFollower
  pure
    { walletNickname
    , companionAppId
    , marloweAppId
    , walletInfo
    , assets: mempty
    }

instance manageMarloweAppM :: ManageMarlowe AppM where
  -- TODO: This code was meant for mock wallet, as part of SCP-3170 we should re-implement this
  --       using the WBE.
  createWallet walletName passphrase = runExceptT do
    -- create the wallet itself
    { mnemonic, walletInfo } <- ExceptT $ Wallet.createWallet walletName
      passphrase
    walletDetails <- fetchWalletDetails walletName walletInfo
    pure { mnemonic, walletDetails }
  restoreWallet walletName mnemonicPhrase passphrase = runExceptT do
    walletInfo <- ExceptT $ Wallet.restoreWallet
      { walletName: WN.toString walletName
      , mnemonicPhrase: map Word.toString $ MP.toWords mnemonicPhrase
      , passphrase
      }
    fetchWalletDetails walletName walletInfo

  -- create a MarloweFollower app, call its "follow" endpoint with the given MarloweParams, and then
  -- return its PlutusAppId and observable state
  followContract walletDetails marloweParams =
    runExceptT do
      let
        walletId = view (_walletInfo <<< _walletId) walletDetails
      followAppId <- withExceptT Left $ ExceptT $ PAB.activateContract
        MarloweFollower
        walletId
      void $ withExceptT Left $ ExceptT $ PAB.invokeEndpoint followAppId
        "follow"
        marloweParams
      observableStateJson <- withExceptT Left $ ExceptT $
        PAB.getContractInstanceObservableState followAppId
      observableState <-
        except
          $ lmap Right
          $ parseDecodeJson
          $ unwrap observableStateJson
      pure $ followAppId /\ observableState
  -- create a MarloweFollower app and return its PlutusAppId, but don't call its "follow" endpoint
  -- (this function is used for creating "placeholder" contracts before we know the MarloweParams)
  createPendingFollowerApp walletDetails =
    let
      walletId = view (_walletInfo <<< _walletId) walletDetails
    in
      PAB.activateContract MarloweFollower walletId
  -- call the "follow" endpoint of a pending MarloweFollower app, and return its PlutusAppId and
  -- observable state (to call this function, we must already know its PlutusAppId, but we return
  -- it anyway because it is convenient to have this function return the same type as
  -- `followContract`)
  followContractWithPendingFollowerApp _ marloweParams followerAppId =
    runExceptT do
      void $ withExceptT Left $ ExceptT $ PAB.invokeEndpoint followerAppId
        "follow"
        marloweParams
      observableStateJson <-
        withExceptT Left $ ExceptT $ PAB.getContractInstanceObservableState
          followerAppId
      observableState <-
        except
          $ lmap Right
          $ parseDecodeJson
          $ unwrap observableStateJson
      pure $ followerAppId /\ observableState
  -- "create" a Marlowe contract on the blockchain
  -- FIXME: if we want users to be able to follow contracts that they don't have roles in, we need this function
  -- to return the MarloweParams of the created contract - but this isn't currently possible in the PAB
  -- UPDATE to this FIXME: it is possible this won't be a problem, as it seems role tokens are first paid into
  -- the wallet that created the contract, and distributed to other wallets from there - but this remains to be
  -- seen when all the parts are working together as they should be...
  createContract walletDetails roles contract =
    let
      marloweAppId = view _marloweAppId walletDetails
    in
      MarloweApp.createContract marloweAppId roles contract
  -- "apply-inputs" to a Marlowe contract on the blockchain
  applyTransactionInput walletDetails marloweParams transactionInput =
    let
      marloweAppId = view _marloweAppId walletDetails
    in
      MarloweApp.applyInputs marloweAppId marloweParams transactionInput
  -- "redeem" payments from a Marlowe contract on the blockchain
  redeem walletDetails marloweParams tokenName =
    let
      marloweAppId = view _marloweAppId walletDetails

      address = view (_walletInfo <<< _pubKeyHash) walletDetails
    in
      MarloweApp.redeem marloweAppId marloweParams tokenName address

  -- get the observable state of a wallet's WalletCompanion
  getRoleContracts walletDetails =
    runExceptT do
      let
        companionAppId = view _companionAppId walletDetails
      observableStateJson <- withExceptT Left $ ExceptT $
        PAB.getContractInstanceObservableState companionAppId
      except $ lmap Right $ parseDecodeJson $ unwrap observableStateJson
  -- get all MarloweFollower apps for a given wallet
  getFollowerApps walletDetails =
    runExceptT do
      let
        walletId = view (_walletInfo <<< _walletId) walletDetails
      runningApps <- withExceptT Left $ ExceptT $
        PAB.getWalletContractInstances walletId
      let
        followerApps = Array.filter
          (\cic -> view _cicDefinition cic == MarloweFollower)
          runningApps
      case traverse decodeFollowerAppState followerApps of
        Left decodingError -> except $ Left $ Right decodingError
        Right decodedFollowerApps -> ExceptT $ pure $ Right $ fromFoldable
          decodedFollowerApps
    where
    decodeFollowerAppState
      :: ContractInstanceClientState MarloweContract
      -> Either JsonDecodeError (Tuple PlutusAppId ContractHistory)
    decodeFollowerAppState contractInstanceClientState =
      let
        plutusAppId = toFront $ view _cicContract contractInstanceClientState

        rawJson = view (_cicCurrentState <<< _observableState)
          contractInstanceClientState
      in
        case parseDecodeJson $ unwrap rawJson of
          Left decodingErrors -> Left decodingErrors
          Right observableState -> Right (plutusAppId /\ observableState)
  subscribeToPlutusApp = toBack >>> Left >>> Subscribe >>> sendWsMessage
  subscribeToWallet =
    toBack
      >>> un Back.Wallet
      >>> _.getWalletId
      >>> (\x -> Back.PubKeyHash { getPubKeyHash: x })
      >>> Right
      >>> Subscribe
      >>> sendWsMessage
  unsubscribeFromPlutusApp = toBack >>> Left >>> Unsubscribe >>> sendWsMessage
  unsubscribeFromWallet =
    toBack
      >>> un Back.Wallet
      >>> _.getWalletId
      >>> (\x -> Back.PubKeyHash { getPubKeyHash: x })
      >>> Right
      >>> Unsubscribe
      >>> sendWsMessage

-- Helper function to the restoreWallet so that we can reutilize the wallet companion or marlowe app if available
activateOrRestorePlutusCompanionContracts
  :: forall m
   . ManagePAB m
  => WalletId
  -> Array (ContractInstanceClientState MarloweContract)
  -> m
       ( AjaxResponse
           { companionAppId :: PlutusAppId, marloweAppId :: PlutusAppId }
       )
activateOrRestorePlutusCompanionContracts walletId plutusContracts = do
  let
    findOrActivateContract :: _ -> m (AjaxResponse PlutusAppId)
    findOrActivateContract contractType =
      -- Try to find the contract by its type
      Array.find (eq contractType <<< view _cicDefinition) plutusContracts
        # maybe'
            -- If we cannot find it, activate a new one
            (\_ -> PAB.activateContract contractType walletId)
            -- If we find it, return the id
            (pure <<< Right <<< fromContractInstanceId <<< view _cicContract)

  ajaxWalletCompanionId <- findOrActivateContract WalletCompanion
  ajaxMarloweAppId <- findOrActivateContract MarloweApp
  pure $ (\companionAppId marloweAppId -> { companionAppId, marloweAppId })
    <$> ajaxWalletCompanionId
    <*> ajaxMarloweAppId

sendWsMessage :: CombinedWSStreamToServer -> AppM Unit
sendWsMessage msg = do
  wsManager <- asks \(Env e) -> e.wsManager
  liftAff
    $ WS.managerWriteOutbound wsManager
    $ WS.SendMessage msg

instance monadMarloweHalogenM ::
  ( ManageMarlowe m
  ) =>
  ManageMarlowe (HalogenM state action slots msg m) where
  createWallet wn p = lift $ createWallet wn p
  restoreWallet = map (map (map lift)) restoreWallet
  followContract walletDetails marloweParams = lift $ followContract
    walletDetails
    marloweParams
  createPendingFollowerApp = lift <<< createPendingFollowerApp
  followContractWithPendingFollowerApp walletDetails marloweParams followAppId =
    lift $ followContractWithPendingFollowerApp
      walletDetails
      marloweParams
      followAppId
  createContract walletDetails roles contract =
    lift $ createContract walletDetails roles contract
  applyTransactionInput walletDetails marloweParams transactionInput =
    lift $ applyTransactionInput walletDetails marloweParams transactionInput
  redeem walletDetails marloweParams tokenName =
    lift $ redeem walletDetails marloweParams tokenName
  getRoleContracts = lift <<< getRoleContracts
  getFollowerApps = lift <<< getFollowerApps
  subscribeToPlutusApp = lift <<< subscribeToPlutusApp
  subscribeToWallet = lift <<< subscribeToWallet
  unsubscribeFromPlutusApp = lift <<< unsubscribeFromPlutusApp
  unsubscribeFromWallet = lift <<< unsubscribeFromWallet
