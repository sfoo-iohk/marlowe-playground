module StaticAnalysis.StaticTools
  ( analyseContract
  , closeZipperContract
  , countSubproblems
  , getNextSubproblem
  , initSubproblems
  , startMultiStageAnalysis
  , zipperToContractPath
  ) where

import Prologue hiding (div)

import Analytics (class IsEvent, analyticsTracking)
import Control.Monad.Trans.Class (lift)
import Data.Bifunctor (lmap)
import Data.BigInt.Argonaut (BigInt, toNumber)
import Data.Lens (assign, use)
import Data.List (List(..), foldl, fromFoldable, length, snoc, toUnfoldable)
import Data.List as List
import Data.List.Types (NonEmptyList(..))
import Data.NonEmpty ((:|))
import Data.Traversable (traverse)
import Data.Tuple.Nested (type (/\), (/\))
import Effect.Aff.Class (class MonadAff)
import Halogen (HalogenM, liftEffect)
import Language.Marlowe.Core.V1.Semantics (emptyState)
import Language.Marlowe.Core.V1.Semantics.Types
  ( Case(..)
  , Contract(..)
  , Observation(..)
  )
import Language.Marlowe.Core.V1.Semantics.Types as S
import Language.Marlowe.Extended.V1 (toCore)
import Language.Marlowe.Extended.V1 as EM
import Marlowe (Api)
import Marlowe as Server
import Marlowe.Symbolic.Types.Request as MSReq
import Marlowe.Symbolic.Types.Response (Response(..), Result(..))
import Marlowe.Template (fillTemplate)
import Network.RemoteData (RemoteData(..), fromEither)
import Servant.PureScript (class MonadAjax)
import StaticAnalysis.Types
  ( AnalysisExecutionState(..)
  , AnalysisInProgressRecord
  , AnalysisState
  , ContractPath
  , ContractPathStep(..)
  , ContractZipper(..)
  , MultiStageAnalysisData(..)
  , MultiStageAnalysisProblemDef
  , RemainingSubProblemInfo
  , _analysisExecutionState
  , _analysisState
  , _templateContent
  )
import Types (JsonAjaxError, WarningAnalysisError(..))

analyseContract
  :: forall m state action slots
   . MonadAff m
  => MonadAjax Api m
  => EM.Contract
  -> HalogenM { analysisState :: AnalysisState | state } action slots Void m
       Unit
analyseContract extendedContract = do
  templateContent <- use (_analysisState <<< _templateContent)
  case toCore $ fillTemplate templateContent extendedContract of
    Just contract -> do
      assign (_analysisState <<< _analysisExecutionState)
        (WarningAnalysis Loading)
      -- when editor and simulator were together the analyse contract could be made
      -- at any step of the simulator. Now that they are separate, it can only be done
      -- with initial state
      response <- checkContractForWarnings emptyState contract
      assign (_analysisState <<< _analysisExecutionState) $ WarningAnalysis
        $ lmap WarningAnalysisAjaxError
        $ fromEither
        $ response
    Nothing -> assign (_analysisState <<< _analysisExecutionState)
      $ WarningAnalysis
      $ Failure WarningAnalysisIsExtendedMarloweError
  where
  checkContractForWarnings state contract =
    traverse logAndStripDuration =<< lift
      ( Server.postApiMarloweanalysis
          $ MSReq.Request { onlyAssertions: false, contract, state }
      )

splitArray :: forall a. List a -> List (List a /\ a /\ List a)
splitArray x = splitArrayAux Nil x

splitArrayAux :: forall a. List a -> List a -> List (List a /\ a /\ List a)
splitArrayAux _ Nil = Nil

splitArrayAux l (Cons h t) = Cons (l /\ h /\ t) (splitArrayAux (Cons h l) t)

expandChildren :: ContractZipper -> Contract -> RemainingSubProblemInfo
expandChildren _ Close = Nil

expandChildren zipper (Pay accId payee tok val cont) = Cons
  (PayZip accId payee tok val zipper /\ cont)
  Nil

expandChildren zipper (If obs cont1 cont2) = Cons
  (IfTrueZip obs zipper cont2 /\ cont1)
  (Cons (IfFalseZip obs cont1 zipper /\ cont2) Nil)

expandChildren zipper (When cases tim tcont) =
  snoc
    ( List.catMaybes $ splitArray (fromFoldable cases) <#> case _ of
        (before /\ Case act cont /\ after) ->
          Just $ WhenCaseZip before act zipper after tim tcont /\ cont
        (_ /\ MerkleizedCase _ _ /\ _) ->
          Nothing
    )
    (WhenTimeoutZip cases tim zipper /\ tcont)

expandChildren zipper (Let valId val cont) = Cons
  (LetZip valId val zipper /\ cont)
  Nil

expandChildren zipper (Assert obs cont) = Cons (AssertZip obs zipper /\ cont)
  Nil

closeZipperContract :: ContractZipper -> Contract -> Contract
closeZipperContract (PayZip accId payee tok val zipper) cont =
  closeZipperContract zipper (Pay accId payee tok val cont)

closeZipperContract (IfTrueZip obs zipper cont2) cont1 = closeZipperContract
  zipper
  (If obs cont1 cont2)

closeZipperContract (IfFalseZip obs cont1 zipper) cont2 = closeZipperContract
  zipper
  (If obs cont1 cont2)

closeZipperContract (WhenCaseZip bef act zipper aft tim timcont) cont =
  let
    thisCase = Case act cont

    cases = toUnfoldable (foldl (flip Cons) (Cons thisCase aft) bef)
  in
    closeZipperContract zipper (When cases tim timcont)

closeZipperContract (WhenTimeoutZip cases tim zipper) timcont =
  closeZipperContract zipper (When cases tim timcont)

closeZipperContract (LetZip valId val zipper) cont = closeZipperContract zipper
  (Let valId val cont)

closeZipperContract (AssertZip obs zipper) cont = closeZipperContract zipper
  (Assert obs cont)

closeZipperContract HeadZip cont = cont

zipperToContractPathAux :: ContractZipper -> ContractPath -> ContractPath
zipperToContractPathAux (PayZip _ _ _ _ zipper) p = zipperToContractPathAux
  zipper
  (Cons PayContPath p)

zipperToContractPathAux (IfTrueZip _ zipper _) p = zipperToContractPathAux
  zipper
  (Cons IfTruePath p)

zipperToContractPathAux (IfFalseZip _ _ zipper) p = zipperToContractPathAux
  zipper
  (Cons IfFalsePath p)

zipperToContractPathAux (WhenCaseZip bef _ zipper _ _ _) p =
  zipperToContractPathAux zipper (Cons (WhenCasePath (length bef)) p)

zipperToContractPathAux (WhenTimeoutZip _ _ zipper) p = zipperToContractPathAux
  zipper
  (Cons WhenTimeoutPath p)

zipperToContractPathAux (LetZip _ _ zipper) p = zipperToContractPathAux zipper
  (Cons LetPath p)

zipperToContractPathAux (AssertZip _ zipper) p = zipperToContractPathAux zipper
  (Cons AssertPath p)

zipperToContractPathAux HeadZip p = p

zipperToContractPath :: ContractZipper -> ContractPath
zipperToContractPath zipper = zipperToContractPathAux zipper Nil

nullifyAsserts :: Contract -> Contract
nullifyAsserts Close = Close

nullifyAsserts (Pay accId payee tok val cont) = Pay accId payee tok val
  (nullifyAsserts cont)

nullifyAsserts (If obs cont1 cont2) = If obs (nullifyAsserts cont1)
  (nullifyAsserts cont2)

nullifyAsserts (When cases timeout timCont) =
  When
    ( cases <#> case _ of
        Case act cont -> Case act (nullifyAsserts cont)
        mc@(MerkleizedCase _ _) -> mc
    )
    timeout
    (nullifyAsserts timCont)

nullifyAsserts (Let valId val cont) = Let valId val (nullifyAsserts cont)

nullifyAsserts (Assert _ cont) = Assert TrueObs cont

initSubproblems :: Contract -> RemainingSubProblemInfo
initSubproblems c = Cons (HeadZip /\ c) Nil

countFix :: forall a. (a -> Maybe a) -> a -> Int
countFix fun a0 = countFix_tailrec fun a0 0
  where
  countFix_tailrec :: (a -> Maybe a) -> a -> Int -> Int
  countFix_tailrec f a acc = case f a of
    Nothing -> acc
    Just newA -> countFix_tailrec f newA (acc + 1)

countSubproblems
  :: (ContractZipper -> Contract -> Boolean) -> RemainingSubProblemInfo -> Int
countSubproblems _ Nil = 0

countSubproblems filterFun subproblemInfo = countFix fixpointFun
  (Nil /\ subproblemInfo)
  where
  fixpointFun
    :: (RemainingSubProblemInfo /\ RemainingSubProblemInfo)
    -> Maybe (RemainingSubProblemInfo /\ RemainingSubProblemInfo)
  fixpointFun (children /\ subproblems) =
    map (\((_ /\ _ /\ c) /\ a) -> (c /\ a)) $ getNextSubproblem filterFun
      subproblems
      children

getNextSubproblem
  :: (ContractZipper -> Contract -> Boolean)
  -> RemainingSubProblemInfo
  -> RemainingSubProblemInfo
  -> Maybe
       ( (ContractZipper /\ Contract /\ RemainingSubProblemInfo) /\
           RemainingSubProblemInfo
       )
getNextSubproblem _ Nil Nil = Nothing

getNextSubproblem f (Cons (zipper /\ contract) rest) Nil =
  if f zipper contract then
    Just ((zipper /\ contract /\ children) /\ rest)
  else
    getNextSubproblem f rest children
  where
  children = expandChildren zipper contract

getNextSubproblem f acc newChildren = getNextSubproblem f (acc <> newChildren)
  Nil

data StaticAnalysisEvent = StaticAnalysisTimingEvent BigInt

instance isEventStaticAnalysisEvent :: IsEvent StaticAnalysisEvent where
  toEvent (StaticAnalysisTimingEvent durationMs) =
    Just
      ( { action: "timing_complete"
        , category: Just "Static Analysis"
        , label: Just "Duration of analysis"
        , value: Just $ toNumber durationMs
        }
      )

logAndStripDuration
  :: forall m state action slots
   . MonadAff m
  => Response
  -> HalogenM state action slots Void m Result
logAndStripDuration (Response { result, durationMs }) = do
  liftEffect $ analyticsTracking (StaticAnalysisTimingEvent durationMs)
  pure result

checkContractForFailedAssertions
  :: forall m state action slots
   . MonadAff m
  => MonadAjax Api m
  => Contract
  -> S.State
  -> HalogenM state action slots Void m (Either JsonAjaxError Result)
checkContractForFailedAssertions contract state =
  traverse logAndStripDuration =<< lift
    ( Server.postApiMarloweanalysis
        $ MSReq.Request
            { onlyAssertions: true, contract: contract, state: state }
    )

startMultiStageAnalysis
  :: forall m state action slots
   . MonadAff m
  => MultiStageAnalysisProblemDef
  -> MonadAjax Api m
  => Contract
  -> S.State
  -> HalogenM { analysisState :: AnalysisState | state } action slots Void m
       MultiStageAnalysisData
startMultiStageAnalysis problemDef contract state = do
  case
    getNextSubproblem (problemDef.isValidSubproblemImpl) initialSubproblems Nil
    of
    Nothing -> pure AnalysisFinishedAndPassed
    Just ((contractZipper /\ subContract /\ newChildren) /\ newSubproblems) ->
      do
        let
          numSubproblems = countSubproblems problemDef.isValidSubproblemImpl
            (newChildren <> newSubproblems)

          newPath /\ newContract = problemDef.expandSubproblemImpl
            contractZipper
            subContract

          progress =
            ( AnalysisInProgress
                { currPath: newPath
                , currContract: newContract
                , currChildren: newChildren
                , originalState: state
                , originalContract: contract
                , subproblems: newSubproblems
                , numSubproblems: 1 + numSubproblems
                , numSolvedSubproblems: 0
                , counterExampleSubcontracts: Nil
                }
            )
        assign (_analysisState <<< _analysisExecutionState)
          (problemDef.analysisDataSetter progress)
        response <- checkContractForFailedAssertions newContract state
        result <- updateWithResponse problemDef progress response
        pure result
  where
  initialSubproblems = initSubproblems contract

stepSubproblem
  :: MultiStageAnalysisProblemDef
  -> Boolean
  -> AnalysisInProgressRecord
  -> Boolean /\ AnalysisInProgressRecord
stepSubproblem
  problemDef
  isCounterExample
  ( rad@
      { currPath: oldPath
      , subproblems: oldSubproblems
      , currChildren: oldChildren
      , numSolvedSubproblems: n
      , numSubproblems: oldTotalN
      , counterExampleSubcontracts: results
      }
  ) =
  case
    getNextSubproblem problemDef.isValidSubproblemImpl oldSubproblems
      (if willExamineChildren then oldChildren else Nil)
    of
    Just ((contractZipper /\ subcontract /\ newChildren) /\ newSubproblems) ->
      let
        newPath /\ newContract = problemDef.expandSubproblemImpl contractZipper
          subcontract
      in
        true
          /\
            ( rad
                { currPath = newPath
                , currContract = newContract
                , currChildren = newChildren
                , subproblems = newSubproblems
                , numSolvedSubproblems = newN
                , numSubproblems = newTotalN
                , counterExampleSubcontracts = newResults
                }
            )
    Nothing ->
      false
        /\
          ( rad
              { subproblems = Nil
              , numSolvedSubproblems = newN
              , numSubproblems = newTotalN
              , counterExampleSubcontracts = newResults
              }
          )
  where
  willExamineChildren = problemDef.shouldExamineChildren isCounterExample

  isProblemCounterExample = problemDef.isProblemCounterExample isCounterExample

  newN = n + 1

  newTotalN = oldTotalN -
    ( if willExamineChildren then 0
      else countSubproblems problemDef.isValidSubproblemImpl oldChildren
    )

  newResults = results <>
    (if isProblemCounterExample then Nil else Cons oldPath Nil)

updateWithResponse
  :: forall m state action slots
   . MonadAff m
  => MonadAjax Api m
  => MultiStageAnalysisProblemDef
  -> MultiStageAnalysisData
  -> Either JsonAjaxError Result
  -> HalogenM
       { analysisState :: AnalysisState | state }
       action
       slots
       Void
       m
       MultiStageAnalysisData
updateWithResponse _ (AnalysisInProgress _) (Left _) = pure
  (AnalysisFailure "connection error")

updateWithResponse _ (AnalysisInProgress _) (Right (Error err)) = pure
  (AnalysisFailure err)

updateWithResponse problemDef (AnalysisInProgress rad) (Right Valid) =
  stepAnalysis problemDef false rad

updateWithResponse
  problemDef
  (AnalysisInProgress rad)
  (Right (CounterExample _)) = stepAnalysis problemDef true rad

updateWithResponse _ rad _ = pure rad

finishAnalysis :: AnalysisInProgressRecord -> MultiStageAnalysisData
finishAnalysis
  { originalState, originalContract, counterExampleSubcontracts: Cons h t } =
  AnalysisFoundCounterExamples
    { originalState
    , originalContract
    , counterExampleSubcontracts: NonEmptyList (h :| t)
    }

finishAnalysis { counterExampleSubcontracts: Nil } = AnalysisFinishedAndPassed

stepAnalysis
  :: forall m state action slots
   . MonadAff m
  => MultiStageAnalysisProblemDef
  -> MonadAjax Api m
  => Boolean
  -> AnalysisInProgressRecord
  -> HalogenM { analysisState :: AnalysisState | state } action slots Void m
       MultiStageAnalysisData
stepAnalysis problemDef isCounterExample rad =
  let
    thereAreMore /\ newRad = stepSubproblem problemDef isCounterExample rad
  in
    if thereAreMore then do
      assign (_analysisState <<< _analysisExecutionState)
        (problemDef.analysisDataSetter (AnalysisInProgress newRad))
      response <- checkContractForFailedAssertions (newRad.currContract)
        (newRad.originalState)
      updateWithResponse problemDef (AnalysisInProgress newRad) response
    else do
      let
        result = finishAnalysis newRad
      assign (_analysisState <<< _analysisExecutionState)
        (problemDef.analysisDataSetter result)
      pure result
