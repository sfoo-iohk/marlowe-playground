{-# LANGUAGE OverloadedStrings #-}
module EscrowWithCollateral where

import Language.Marlowe.Core.V1.Semantics.Types.Address (testnet)
import Language.Marlowe.Extended.V1
import qualified Plutus.V1.Ledger.Address as P
import qualified Plutus.V1.Ledger.Credential as P

main :: IO ()
main = printJSON escrowC

-- We can set explicitRefunds True to run Close refund analysis
-- but we get a shorter contract if we set it to False
explicitRefunds :: Bool
explicitRefunds = False

seller, buyer, burnAddress :: Party
buyer = Role "Buyer"
seller = Role "Seller"
burnAddress = Address testnet (P.Address (P.PubKeyCredential "0000000000000000000000000000000000000000000000000000000000000000") Nothing)

price, collateral :: Value
price = ConstantParam "Price"
collateral = ConstantParam "Collateral amount"

sellerCollateralTimeout, buyerCollateralTimeout, depositTimeout, disputeTimeout, answerTimeout :: Timeout
sellerCollateralTimeout = TimeParam "Collateral deposit by seller timeout"
buyerCollateralTimeout = TimeParam "Deposit of collateral by buyer timeout"
depositTimeout = TimeParam "Deposit of price by buyer timeout"
disputeTimeout = TimeParam "Dispute by buyer timeout"
answerTimeout = TimeParam "Complaint deadline"

depositCollateral :: Party -> Timeout -> Contract -> Contract -> Contract
depositCollateral party timeout timeoutContinuation continuation =
    When [Case (Deposit party party ada collateral) continuation]
         timeout
         timeoutContinuation

burnCollaterals :: Contract -> Contract
burnCollaterals =
    Pay seller (Party burnAddress) ada collateral
    . Pay buyer (Party burnAddress) ada collateral

deposit :: Timeout -> Contract -> Contract -> Contract
deposit timeout timeoutContinuation continuation =
    When [Case (Deposit seller buyer ada price) continuation]
         timeout
         timeoutContinuation

choice :: ChoiceName -> Party -> Integer -> Contract -> Case
choice choiceName chooser choiceValue = Case (Choice (ChoiceId choiceName chooser)
                                                     [Bound choiceValue choiceValue])

choices :: Timeout -> Party -> Contract -> [(Integer, ChoiceName, Contract)] -> Contract
choices timeout chooser timeoutContinuation list =
    When [choice choiceName chooser choiceValue continuation
          | (choiceValue, choiceName, continuation) <- list]
         timeout
         timeoutContinuation

sellerToBuyer :: Contract -> Contract
sellerToBuyer = Pay seller (Account buyer) ada price

refundSellerCollateral :: Contract -> Contract
refundSellerCollateral
  | explicitRefunds = Pay seller (Party seller) ada collateral
  | otherwise = id

refundBuyerCollateral :: Contract -> Contract
refundBuyerCollateral
  | explicitRefunds = Pay buyer (Party buyer) ada collateral
  | otherwise = id

refundCollaterals :: Contract -> Contract
refundCollaterals = refundSellerCollateral . refundBuyerCollateral

refundBuyer :: Contract
refundBuyer
 | explicitRefunds = Pay buyer (Party buyer) ada price Close
 | otherwise = Close

refundSeller :: Contract
refundSeller
 | explicitRefunds = Pay seller (Party seller) ada price Close
 | otherwise = Close

escrowC :: Contract
escrowC = depositCollateral seller sellerCollateralTimeout Close $
           depositCollateral buyer buyerCollateralTimeout (refundSellerCollateral Close) $
           deposit depositTimeout (refundCollaterals Close) $
           choices disputeTimeout buyer (refundCollaterals refundSeller)
              [ (0, "Everything is alright"
                , refundCollaterals refundSeller
                )
              , (1, "Report problem"
                , sellerToBuyer $
                  choices answerTimeout seller (refundCollaterals refundBuyer)
                     [ (1, "Confirm problem"
                       , refundCollaterals refundBuyer
                       )
                     , (0, "Dispute problem"
                       , burnCollaterals refundBuyer
                       )
                     ]
                )
              ]
