module MainFrame.State (mkMainFrame, handleAction) where

import Prologue

import API.Lenses
  ( _cicContract
  , _cicCurrentState
  , _cicDefinition
  , _cicStatus
  , _observableState
  )
import Capability.MainFrameLoop (class MainFrameLoop)
import Capability.Marlowe
  ( class ManageMarlowe
  , followContract
  , subscribeToPlutusApp
  , subscribeToWallet
  , unsubscribeFromPlutusApp
  , unsubscribeFromWallet
  )
import Capability.MarloweStorage
  ( class ManageMarloweStorage
  , getWallet
  , updateWallet
  )
import Capability.PAB (class ManagePAB, onNewActiveEndpoints)
import Capability.PAB as PAB
import Capability.PlutusApps.FollowerApp as FollowerApp
import Capability.PlutusApps.MarloweApp.Types (MarloweEndpointResponse)
import Capability.Toast (class Toast, addToast)
import Clipboard (class MonadClipboard)
import Control.Logger.Capability (class MonadLogger)
import Control.Logger.Capability as Logger
import Control.Monad.Except (ExceptT(..), runExceptT)
import Control.Monad.Maybe.Trans (MaybeT(..), runMaybeT)
import Control.Monad.Reader (class MonadAsk, asks)
import Control.Monad.State (class MonadState)
import Data.AddressBook as AddressBook
import Data.Argonaut (Json, decodeJson, printJsonDecodeError, stringify)
import Data.Array (filter, find) as Array
import Data.Array (head, mapMaybe, partition)
import Data.Either (hush)
import Data.Foldable (for_, traverse_)
import Data.Lens (_1, assign, lens, preview, set, use, view, (^.), (^?))
import Data.Lens.Extra (peruse)
import Data.Maybe (fromMaybe, maybe)
import Data.PABConnectedWallet (PABConnectedWallet, connectWallet)
import Data.PABConnectedWallet as Connected
import Data.String (joinWith)
import Data.Time.Duration (Milliseconds(..), Minutes(..))
import Data.Traversable (traverse)
import Data.Tuple.Nested (type (/\), (/\))
import Data.Wallet (SyncStatus(..), WalletDetails)
import Data.Wallet as Disconnected
import Data.WalletId (WalletId)
import Effect.Aff (bracket, delay)
import Effect.Aff.AVar as AVar
import Effect.Aff.Class (class MonadAff, liftAff)
import Env (Env, _pendingResults, _pollingInterval)
import Halogen (Component, HalogenM, defaultEval, mkComponent, mkEval)
import Halogen as H
import Halogen.Extra (imapState)
import Halogen.Query.HalogenM (mapAction)
import Halogen.Store.Connect (Connected, connect)
import Halogen.Store.Monad (class MonadStore, updateStore)
import Halogen.Store.Select (selectEq)
import Language.Marlowe.Client (EndpointResponse(..), MarloweEndpointResult(..))
import MainFrame.Lenses
  ( _addressBook
  , _currentSlot
  , _dashboardState
  , _store
  , _subState
  , _tzOffset
  , _webSocketStatus
  , _welcomeState
  )
import MainFrame.Types
  ( Action(..)
  , ChildSlots
  , Input
  , Msg
  , Query(..)
  , Slice
  , State
  , WebSocketStatus(..)
  )
import MainFrame.View (render)
import Marlowe.Client (ContractHistory, _chParams, getContract)
import Marlowe.Deinstantiate (findTemplate)
import Marlowe.PAB (PlutusAppId)
import MarloweContract (MarloweContract(..))
import Page.Dashboard.State (handleAction, mkInitialState) as Dashboard
import Page.Dashboard.State (updateTotalFunds)
import Page.Dashboard.Types (Action(..), State) as Dashboard
import Page.Welcome.State (handleAction, initialState) as Welcome
import Page.Welcome.Types (Action, State) as Welcome
import Plutus.PAB.Webserver.Types (ContractInstanceClientState)
import Store (_contracts, _wallet)
import Store as Store
import Store.Contracts (emptyContractStore)
import Store.Wallet (WalletStore(..), _Connected, _connectedWallet, _walletId)
import Store.Wallet as Wallet
import Store.Wallet as WalletStore
import Toast.Types (ajaxErrorToast, errorToast, infoToast, successToast)
import Types (AjaxResponse)
import Wallet.Types (ContractActivityStatus(..))

{-
The Marlowe Run App features are defined in the docs/use-cases/Readme.md file, and they have indices
that can be searched throughout the code.

There are two main application states: the `Welcome` state (UC-WALLET-TESTNET-1 and UC-WALLET-TESTNET-2),
and the `Dashboard` state (for the rest of the use cases). The application starts in the `Welcome` state.
Creating or restoring a wallet moves you into the `Dashboard` state; disconnecting a wallet (UC-WALLET-3)
moves you back into the `Welcome` state.
-}
mkMainFrame
  :: forall m
   . MonadAff m
  => MonadLogger String m
  => MonadAsk Env m
  => MonadStore Store.Action Store.Store m
  => ManageMarlowe m
  => Toast m
  => MonadClipboard m
  => MainFrameLoop m
  => Component Query Input Msg m
mkMainFrame =
  connect
    ( selectEq \{ addressBook, wallet, contracts } ->
        { addressBook, wallet, contracts }
    ) $
    mkComponent
      { initialState: deriveState emptyState
      , render: render
      , eval:
          mkEval defaultEval
            { handleQuery = handleQuery
            , handleAction = handleAction
            , receive = Just <<< Receive
            , initialize = Just Init
            }
      }

emptyState :: State
emptyState =
  { tzOffset: Minutes 0.0 -- this will be updated in deriveState
  , webSocketStatus: WebSocketClosed Nothing
  , currentSlot: zero -- this will be updated as soon as the websocket connection is working
  , subState: Left Welcome.initialState
  , store:
      { addressBook: AddressBook.empty
      , wallet: Disconnected
      , contracts: emptyContractStore
      }
  }

deriveState :: State -> Connected Slice Input -> State
deriveState state { context, input } = state
  { subState = case state.subState of
      Right ds -> Right ds
      Left ws -> Left ws
  , tzOffset = input.tzOffset
  , store =
      { addressBook: context.addressBook
      , wallet: context.wallet
      , contracts: context.contracts
      }
  }

-- When a MarloweApp emits a new observable state, it comes with the information of which
-- request id originated the change. We use this function to update the request queue and
-- free any thread that might be waiting for the result of an action.
-- The return type is a Maybe of the same input, if the value is Nothing, then we couldn't
-- find a request that triggered this response. This can happen for example when reloading
-- the webpage, or if we have two browsers with the same wallet.
fulfillPendingResult
  :: forall m
   . MonadAff m
  => MonadAsk Env m
  => MarloweEndpointResponse
  -> m (Maybe (MarloweEndpointResponse))
fulfillPendingResult response = do
  pendingResultsAvar <- asks $ view _pendingResults
  liftAff
    $ bracket
        (partition (eq reqId <<< fst) <$> AVar.take pendingResultsAvar)
        (flip AVar.put pendingResultsAvar <<< _.no)
        ( _.yes >>> head >>> map snd >>> traverse \pendingResult -> do
            AVar.put response pendingResult
            pure response
        )
  where
  reqId = case response of
    EndpointSuccess rid _ -> rid
    EndpointException rid _ _ -> rid

handleQuery
  :: forall a m
   . MonadAff m
  => MonadLogger String m
  => MonadAsk Env m
  => ManageMarlowe m
  => MonadStore Store.Action Store.Store m
  => Toast m
  => MonadClipboard m
  => MainFrameLoop m
  => Query a
  -> HalogenM State Action ChildSlots Msg m (Maybe a)
handleQuery = case _ of
  MainFrameActionQuery action next -> do
    handleAction action
    pure $ Just next

  GetWallet next -> do
    map (map next) $ peruse $ _store <<< _wallet <<< _Connected

  NewWebSocketStatus status next -> do
    assign _webSocketStatus status
    case status of
      WebSocketOpen -> do
        -- potentially renew websocket subscriptions
        mDashboardState <- peruse _dashboardState
        mWalletId <- peruse $ _store <<< _wallet <<< WalletStore._walletId
        let walletIdXDashboardState = Tuple <$> mWalletId <*> mDashboardState
        for_ walletIdXDashboardState \(Tuple walletId _dashboardState) -> do
          -- TODO: SCP-3543 Encapsultate subscribe/unsubscribe logic into a capability
          subscribeToWallet walletId
          ajaxPlutusApps <- PAB.getWalletContractInstances walletId
          case ajaxPlutusApps of
            Left _ -> pure unit
            Right plutusApps -> for_
              (Array.filter (eq Active <<< view _cicStatus) plutusApps)
              \app ->
                subscribeToPlutusApp $ view _cicContract app
      -- TODO: Consider whether we should show an error/warning when this happens. It might be more
      -- confusing than helpful, since the websocket is automatically reopened if it closes for any
      -- reason.
      _ -> pure unit
    pure $ Just next

  NotificationParseFailed whatFailed error next -> do
    addToast $ errorToast
      ("Failed to parse " <> whatFailed <> " from websocket message")
      (Just $ printJsonDecodeError error)
    pure $ Just next

  SlotChange slot next -> do
    updateStore $ Store.AdvanceToSlot slot
    -- TODO: remove currentSlot from Mainframe once the sub-components are replaced by proper components
    assign _currentSlot slot
    pure $ Just next

  CompanionAppStateUpdated companionAppState next -> do
    handleAction
      $ DashboardAction
      $ Dashboard.UpdateFollowerApps companionAppState
    pure $ Just next

  {- [UC-CONTRACT-1][2] Starting a Marlowe contract
    After the PAB endpoint finishes creating the contract, it modifies
    its observable state with the MarloweParams of the newly created
    contract. We take this opportunity to create a FollowerContract
    that will give us updates on the state of the contract
  -}
  MarloweContractCreated reqId marloweParams next -> runMaybeT $ do
    -- TODO: Return an Aff from the API calls so that the
    --       responses can be awaited at the call site instead.
    _ <- MaybeT
      $ fulfillPendingResult
      $ EndpointSuccess reqId
      $ CreateResponse marloweParams
    wallet <- MaybeT $ peruse $ _store <<< _wallet <<< _Connected
    followContract wallet marloweParams >>= case _ of
      Left _ -> addToast $ errorToast "Can't follow the contract" Nothing
      Right (_ /\ _) -> do
        -- TODO: SCP-3487 swap store contract from new to running
        addToast $ successToast "Contract initialised."
    pure next
  InputsApplied reqId next -> runMaybeT $ do
    -- TODO: Return an Aff from the API calls so that the
    --       responses can be awaited at the call site instead.
    _ <- MaybeT
      $ fulfillPendingResult
      $ EndpointSuccess reqId ApplyInputsResponse
    addToast $ successToast "Contract update applied."
    pure next

  PaymentRedeemed reqId next -> runMaybeT $ do
    -- TODO: Return an Aff from the API calls so that the
    --       responses can be awaited at the call site instead.
    _ <- MaybeT
      $ fulfillPendingResult
      $ EndpointSuccess reqId RedeemResponse
    addToast $ successToast "Payment from contract redeemed"
    pure next

  CreateFailed reqId error next -> runMaybeT $ do
    -- TODO: Return an Aff from the API calls so that the
    --       responses can be awaited at the call site instead.
    _ <- MaybeT
      $ fulfillPendingResult
      $ EndpointException reqId "create" error
    addToast $ errorToast "Failed to create contract" $ Just $ show error
    pure next

  ApplyInputsFailed reqId error next -> runMaybeT $ do
    -- TODO: Return an Aff from the API calls so that the
    --       responses can be awaited at the call site instead.
    _ <- MaybeT
      $ fulfillPendingResult
      $ EndpointException reqId "apply-inputs-nonmerkleized" error
    addToast $ errorToast "Failed to update contract" $ Just $ show error
    pure next

  RedeemFailed reqId error next -> runMaybeT $ do
    -- TODO: Return an Aff from the API calls so that the
    --       responses can be awaited at the call site instead.
    _ <- MaybeT
      $ fulfillPendingResult
      $ EndpointException reqId "redeem" error
    addToast $ errorToast "Failed to redeem payment" $ Just $ show error
    pure next

  ContractHistoryUpdated plutusAppId contractHistory next -> do
    let marloweParams = view (_chParams <<< _1) contractHistory
    {- [UC-CONTRACT-1][3] Start a contract -}
    {- [UC-CONTRACT-3][1] Apply an input to a contract -}
    FollowerApp.onNewObservableState plutusAppId contractHistory
    {- [UC-CONTRACT-4][0] Redeem payments -}
    handleAction $ DashboardAction $ Dashboard.RedeemPayments marloweParams
    pure $ Just next

  NewActiveEndpoints plutusAppId activeEndpoints next -> do
    -- TODO move into main directly and remove this from the PAB capability API
    onNewActiveEndpoints plutusAppId activeEndpoints
    pure $ Just next

  MarloweAppClosed mVal next -> runMaybeT do
    reActivatePlutusScript MarloweApp mVal
    pure next

  WalletCompanionAppClosed mVal next -> runMaybeT do
    reActivatePlutusScript WalletCompanion mVal
    pure next

reActivatePlutusScript
  :: forall m
   . MonadState State m
  => MonadLogger String m
  => MonadStore Store.Action Store.Store m
  => ManagePAB m
  => MarloweContract
  -> Maybe Json
  -> MaybeT m Unit
reActivatePlutusScript contractType mVal = do
  walletId <- MaybeT $ peruse $ _store <<< _wallet <<< _walletId
  Logger.error $ joinWith " "
    [ "Plutus script"
    , show contractType
    , "has closed unexpectedly:"
    , maybe "" stringify mVal
    ]
  newAppId <- MaybeT $ hush <$> PAB.activateContract contractType walletId
  H.lift
    $ updateStore
    $ Store.Wallet
    $ Wallet.OnPlutusScriptChanged contractType newAppId

-- Note [State]: Some actions belong logically in one part of the state, but
-- from the user's point of view in another. For example, the action of picking
-- up a wallet belongs logically in the MainFrame state (because it modifies
-- that state), but from the user's point of view it belongs in the Pickup
-- state (because that's the state the app is in when you perform it). To work
-- around this, we can either make our `handleAction` functions a bit awkward,
-- or our `render` functions a bit awkward. I prefer the former. Hence some
-- submodule actions (triggered straightforwardly in the submodule's `render`
-- functions) are handled by their parent module's `handleAction` function.
handleAction
  :: forall m
   . MonadAff m
  => MonadAsk Env m
  => MonadLogger String m
  => ManageMarlowe m
  => ManageMarloweStorage m
  => Toast m
  => MonadStore Store.Action Store.Store m
  => MonadClipboard m
  => MainFrameLoop m
  => Action
  -> HalogenM State Action ChildSlots Msg m Unit

handleAction Init = do
  {- [UC-WALLET-TESTNET-2][4b] Restore a testnet wallet
  This is another path for "restoring" a wallet. When we initialize the app,
  if we have some wallet details in the local storage, we try to enter the dashboard
  state with it.
  -}
  mWalletDetails <- getWallet
  traverse_
    (updateStore <<< Store.Wallet <<< WalletStore.OnConnect)
    mWalletDetails
  traverse_
    ( \w -> handleAction $ OnPoll
        (view Disconnected._syncStatus w)
        (view Disconnected._walletId w)
    )
    mWalletDetails
  pure unit

handleAction (Receive input) = do
  oldStore <- use _store
  { store } <- H.modify $ flip deriveState input
  -- Persist the wallet details so that when we Init, we can try to recover it
  updateWallet
    $ map
        ( \wallet ->
            (wallet ^. Connected._walletNickname)
              /\ (wallet ^. Connected._walletId)
              /\ (wallet ^. Connected._pubKeyHash)
              /\ (wallet ^. Connected._address)
        )
    $ store ^? _wallet <<< _connectedWallet
  let
    { contracts } = store
  -- React to changes in the wallet store
  case oldStore.wallet, store.wallet of
    Disconnected, Connecting details -> enterDashboardState details
    Connecting _, Connected connectedWallet -> do
      assign _subState $ Right $ Dashboard.mkInitialState contracts
      handleAction $ OnPoll OutOfSync $ connectedWallet ^. Connected._walletId
    Connected _, Disconnecting connectedWallet ->
      enterWelcomeState connectedWallet
    Disconnecting _, Disconnected ->
      assign _subState $ Left Welcome.initialState
    _, _ -> pure unit

handleAction (OnPoll lastSyncStatus walletId) = do
  updateTotalFunds walletId >>= traverse_ \syncStatus -> do
    case lastSyncStatus, syncStatus of
      Synchronizing _, Synchronized -> addToast $ successToast
        "Wallet backend in sync."
      OutOfSync, Synchronizing _ -> addToast $ infoToast
        "Wallet backend synchronizing..."
      _, _ -> pure unit
    updateStore $ Store.Wallet $ Wallet.OnSyncStatusChanged syncStatus
    pollingInterval <- case syncStatus of
      -- We poll more frequently when the wallet backend is synchronizing so we
      -- get more rapid feedback.
      Synchronizing _ -> pure $ Milliseconds 500.0
      _ -> asks $ view _pollingInterval
    H.liftAff $ delay pollingInterval
    newWalletId <-
      peruse $ _store <<< _wallet <<< _Connected <<< Connected._walletId
    when (Just walletId == newWalletId) do
      void $ H.subscribe $ pure $ OnPoll syncStatus walletId

handleAction (WelcomeAction wa) = do
  mWelcomeState <- peruse _welcomeState
  for_ mWelcomeState \ws -> toWelcome ws $ Welcome.handleAction wa

handleAction (DashboardAction da) = void $ runMaybeT $ do
  currentSlot <- H.lift $ use _currentSlot
  tzOffset <- H.lift $ use _tzOffset
  addressBook <- H.lift $ use _addressBook
  contracts <- H.lift $ use (_store <<< _contracts)
  dashboardState <- MaybeT $ peruse _dashboardState
  wallet <- MaybeT $ peruse $ _store <<< _wallet <<< _connectedWallet
  H.lift $ toDashboard dashboardState
    $ Dashboard.handleAction
        { addressBook, currentSlot, tzOffset, wallet, contracts }
        da

{- [UC-WALLET-3][1] Disconnect a wallet
Here we move from the `Dashboard` state to the `Welcome` state. It's very straightfoward - we just
need to unsubscribe from all the apps related to the wallet that was previously connected.
-}
enterWelcomeState
  :: forall m
   . ManageMarlowe m
  => MonadStore Store.Action Store.Store m
  => PABConnectedWallet
  -> HalogenM State Action ChildSlots Msg m Unit
enterWelcomeState walletDetails = do
  let
    walletId = view Connected._walletId walletDetails
  -- We need to unsubscribe from the wallet per se
  unsubscribeFromWallet walletId
  -- And also from the individual plutus apps that we are
  -- subscribed to.
  -- TODO: SCP-3543 Encapsultate subscribe/unsubscribe logic into a capability
  ajaxPlutusApps <- PAB.getWalletContractInstances walletId
  case ajaxPlutusApps of
    Left _ -> pure unit
    Right plutusApps -> for_ plutusApps \app ->
      unsubscribeFromPlutusApp $ view _cicContract app
  updateStore $ Store.Disconnect

{- [UC-WALLET-TESTNET-2][5] Restore a testnet wallet
Here we move the app from the `Welcome` state to the `Dashboard` state. First, however, we query
the PAB to get all the running contracts (`WalletCompanion`, `MarloweApp` and `MarloweFollower`)
and subscribe to notifications.
-}
enterDashboardState
  :: forall m
   . ManagePAB m
  => MonadLogger String m
  => ManageMarlowe m
  => MonadStore Store.Action Store.Store m
  => Toast m
  => WalletDetails
  -> HalogenM State Action ChildSlots Msg m Unit
enterDashboardState disconnectedWallet = do
  let
    walletId = view Disconnected._walletId disconnectedWallet
  ajaxPlutusApps <- PAB.getWalletContractInstances walletId
  -- TODO: Refactor with runExceptT
  case ajaxPlutusApps of
    Left ajaxError -> addToast $ ajaxErrorToast
      "Failed to access the plutus contracts."
      ajaxError
    Right plutusApps -> do
      -- Get notified of wallet messages
      subscribeToWallet $ walletId
      -- Subscribe to WalletCompanion and the MarloweApp control app
      -- we try to reutilize an active plutus contract if possible,
      -- if not we activate new ones
      ajaxCompanionContracts <- activateOrRestorePlutusCompanionContracts
        walletId
        plutusApps
      case ajaxCompanionContracts of
        Left ajaxError -> addToast $ ajaxErrorToast
          "Failed to create the companion plutus contracts."
          ajaxError
        Right { companionAppId, marloweAppId } -> do
          -- TODO: SCP-3543 Encapsultate subscribe/unsubscribe logic into a capability
          -- Get notified of new contracts
          subscribeToPlutusApp companionAppId
          -- Get notified of the results of our control app
          subscribeToPlutusApp marloweAppId
          Logger.info $ "Subscribed to companion app " <> show companionAppId
            <> " and control app "
            <> show marloweAppId
          -- Get notified on contract changes
          let
            connectedWallet = connectWallet { companionAppId, marloweAppId }
              disconnectedWallet
            followerApps = filterFollowerApps plutusApps
          currentSlot <- use _currentSlot
          for_ followerApps \(followerAppId /\ contractHistory) -> do
            subscribeToPlutusApp followerAppId
            let
              contract = getContract contractHistory
              mMetadata = _.metaData <$> findTemplate contract
            for_ mMetadata \metadata ->
              updateStore $ Store.AddFollowerContract
                currentSlot
                followerAppId
                metadata
                contractHistory
          updateStore $ Store.Wallet $ Wallet.OnConnected connectedWallet

------------------------------------------------------------
filterFollowerApps
  :: Array (ContractInstanceClientState MarloweContract)
  -> Array (PlutusAppId /\ ContractHistory)
filterFollowerApps plutusContracts =
  let
    isActiveFollowerContract cic =
      let
        definition = view _cicDefinition cic
        status = view _cicStatus cic
      in
        definition == MarloweFollower && status == Active
    idAndHistory cic =
      let
        plutusId = view _cicContract cic
        observableStateJson = view (_cicCurrentState <<< _observableState) cic
      in
        Tuple plutusId <$> (hush $ decodeJson observableStateJson)
  in
    mapMaybe idAndHistory $ Array.filter isActiveFollowerContract
      plutusContracts

activateOrRestorePlutusCompanionContracts
  :: forall m
   . ManagePAB m
  => WalletId
  -> Array (ContractInstanceClientState MarloweContract)
  -> m
       ( AjaxResponse
           { companionAppId :: PlutusAppId, marloweAppId :: PlutusAppId }
       )
activateOrRestorePlutusCompanionContracts walletId plutusContracts = runExceptT
  do
    let
      isActiveContract contractType cic =
        let
          definition = view _cicDefinition cic
          status = view _cicStatus cic
        in
          definition == contractType && status == Active

      findOrActivateContract contractType =
        -- Try to find the contract by its type
        Array.find (isActiveContract contractType) plutusContracts # case _ of
          Nothing ->
            -- If we cannot find it, activate a new one
            ExceptT $ PAB.activateContract contractType walletId
          Just contract ->
            -- If we find it, return the id
            pure $ view _cicContract contract
    { companionAppId: _, marloweAppId: _ }
      <$> findOrActivateContract WalletCompanion
      <*> findOrActivateContract MarloweApp

------------------------------------------------------------
-- Note [dummyState]: In order to map a submodule whose state might not exist, we need
-- to provide a dummyState for that submodule. Halogen would use this dummyState to play
-- with if we ever tried to call one of these handlers when the submodule state does not
-- exist. In practice this should never happen.
toWelcome
  :: forall m msg slots
   . Functor m
  => Welcome.State
  -> HalogenM Welcome.State Welcome.Action slots msg m Unit
  -> HalogenM State Action slots msg m Unit
toWelcome s = mapAction WelcomeAction <<< imapState (lens getter setter)
  where
  getter = fromMaybe s <<< preview _welcomeState
  setter = flip $ set _welcomeState

toDashboard
  :: forall m msg slots
   . Functor m
  => Dashboard.State
  -> HalogenM Dashboard.State Dashboard.Action slots msg m Unit
  -> HalogenM State Action slots msg m Unit
toDashboard s = mapAction DashboardAction <<< imapState (lens getter setter)
  where
  getter = fromMaybe s <<< preview _dashboardState
  setter = flip $ set _dashboardState
