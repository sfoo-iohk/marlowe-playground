module Marlowe.Blockly where

import Blockly.Dom as BDom
import Blockly.Internal
  ( AlignDirection(..)
  , Arg(..)
  , BlockDefinition(..)
  , Pair(..)
  , clearUndoStack
  , clearWorkspace
  , connect
  , connectToOutput
  , connectToPrevious
  , defaultBlockDefinition
  , fieldName
  , fieldRow
  , getBlockById
  , getInputWithName
  , initializeWorkspace
  , inputList
  , inputName
  , inputType
  , nextConnection
  , previousConnection
  , render
  , setFieldText
  , typedArguments
  )
import Blockly.Toolbox
  ( Category
  , Toolbox(..)
  , category
  , leaf
  , rename
  , separator
  )
import Blockly.Types
  ( Block
  , BlocklyState
  , Connection
  , Input
  , NewBlockFunction
  , Workspace
  )
import Control.Monad.Error.Class (catchError)
import Control.Monad.Error.Extra (toMonadThrow)
import Control.Monad.Except (class MonadError, throwError)
import Control.Monad.Except.Trans (class MonadThrow)
import Data.Array (catMaybes, filter, head, uncons)
import Data.Array as Array
import Data.Bifunctor (lmap)
import Data.BigInt.Argonaut (BigInt)
import Data.BigInt.Argonaut as BigInt
import Data.Bounded.Generic (genericBottom, genericTop)
import Data.DateTime.Instant
  ( Instant
  )
import Data.DateTime.Instant.Extra (bigIntToInstant, instantToBigInt)
import Data.Either (note')
import Data.Enum (class BoundedEnum, class Enum, upFromIncluding)
import Data.Enum.Generic
  ( genericCardinality
  , genericFromEnum
  , genericPred
  , genericSucc
  , genericToEnum
  )
import Data.Eq.Generic (genericEq)
import Data.Foldable (for_)
import Data.Generic.Rep (class Generic)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (maybe)
import Data.Ord.Generic (genericCompare)
import Data.Show.Generic (genericShow)
import Data.TraversableWithIndex (forWithIndex)
import Effect (Effect)
import Foreign.Object as Object
import Marlowe.Holes
  ( Action(..)
  , Bound(..)
  , Case(..)
  , ChoiceId(..)
  , Contract(..)
  , Location(..)
  , Observation(..)
  , Party(..)
  , Payee(..)
  , Term(..)
  , TermWrapper(..)
  , Timeout(..)
  , Token(..)
  , Value(..)
  , ValueId(..)
  )
import Prologue
  ( class Bounded
  , class Eq
  , class Ord
  , class Show
  , Either
  , Maybe(..)
  , Tuple(..)
  , Unit
  , bind
  , bottom
  , discard
  , map
  , pure
  , show
  , unit
  , ($)
  , (<#>)
  , (<$>)
  , (<<<)
  , (<>)
  , (=<<)
  , (==)
  , (>>=)
  )
import Record (merge)

rootBlockName :: String
rootBlockName = "root_contract"

data ActionType
  = DepositActionType
  | ChoiceActionType
  | NotifyActionType

derive instance genericActionType :: Generic ActionType _

instance showActionType :: Show ActionType where
  show = genericShow

instance eqActionType :: Eq ActionType where
  eq = genericEq

instance ordActionType :: Ord ActionType where
  compare = genericCompare

instance enumActionType :: Enum ActionType where
  succ = genericSucc
  pred = genericPred

instance boundedActionType :: Bounded ActionType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumActionType :: BoundedEnum ActionType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

actionTypes :: Array ActionType
actionTypes = upFromIncluding bottom

data PayeeType
  = AccountPayeeType
  | PartyPayeeType

derive instance genericPayeeType :: Generic PayeeType _

instance showPayeeType :: Show PayeeType where
  show = genericShow

instance eqPayeeType :: Eq PayeeType where
  eq = genericEq

instance ordPayeeType :: Ord PayeeType where
  compare = genericCompare

instance enumPayeeType :: Enum PayeeType where
  succ = genericSucc
  pred = genericPred

instance boundedPayeeType :: Bounded PayeeType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumPayeeType :: BoundedEnum PayeeType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

payeeTypes :: Array PayeeType
payeeTypes = upFromIncluding bottom

data PartyType
  = AddressPartyType
  | RolePartyType

derive instance genericPartyType :: Generic PartyType _

instance showPartyType :: Show PartyType where
  show = genericShow

instance eqPartyType :: Eq PartyType where
  eq = genericEq

instance ordPartyType :: Ord PartyType where
  compare = genericCompare

instance enumPartyType :: Enum PartyType where
  succ = genericSucc
  pred = genericPred

instance boundedPartyType :: Bounded PartyType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumPartyType :: BoundedEnum PartyType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

partyTypes :: Array PartyType
partyTypes = upFromIncluding bottom

data TokenType
  = AdaTokenType
  | CustomTokenType

derive instance genericTokenType :: Generic TokenType _

instance showTokenType :: Show TokenType where
  show = genericShow

instance eqTokenType :: Eq TokenType where
  eq = genericEq

instance ordTokenType :: Ord TokenType where
  compare = genericCompare

instance enumTokenType :: Enum TokenType where
  succ = genericSucc
  pred = genericPred

instance boundedTokenType :: Bounded TokenType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumTokenType :: BoundedEnum TokenType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

tokenTypes :: Array TokenType
tokenTypes = upFromIncluding bottom

data ContractType
  = WhenContractType
  | PayContractType
  | IfContractType
  | LetContractType
  | AssertContractType
  | CloseContractType

derive instance genericContractType :: Generic ContractType _

instance showContractType :: Show ContractType where
  show = genericShow

instance eqContractType :: Eq ContractType where
  eq = genericEq

instance ordContractType :: Ord ContractType where
  compare = genericCompare

instance enumContractType :: Enum ContractType where
  succ = genericSucc
  pred = genericPred

instance boundedContractType :: Bounded ContractType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumContractType :: BoundedEnum ContractType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

contractTypes :: Array ContractType
contractTypes = upFromIncluding bottom

data ObservationType
  = AndObservationType
  | OrObservationType
  | NotObservationType
  | ChoseSomethingObservationType
  | ValueGEObservationType
  | ValueGTObservationType
  | ValueLTObservationType
  | ValueLEObservationType
  | ValueEQObservationType
  | TrueObservationType
  | FalseObservationType

derive instance genericObservationType :: Generic ObservationType _

instance showObservationType :: Show ObservationType where
  show = genericShow

instance eqObservationType :: Eq ObservationType where
  eq = genericEq

instance ordObservationType :: Ord ObservationType where
  compare = genericCompare

instance enumObservationType :: Enum ObservationType where
  succ = genericSucc
  pred = genericPred

instance boundedObservationType :: Bounded ObservationType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumObservationType :: BoundedEnum ObservationType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

observationTypes :: Array ObservationType
observationTypes = upFromIncluding bottom

data ValueType
  = AvailableMoneyValueType
  | ConstantValueType
  | ConstantParamValueType
  | NegValueValueType
  | AddValueValueType
  | SubValueValueType
  | MulValueValueType
  | DivValueValueType
  | ChoiceValueValueType
  | TimeIntervalStartValueType
  | TimeIntervalEndValueType
  | UseValueValueType
  | CondObservationValueValueType

derive instance genericValueType :: Generic ValueType _

instance showValueType :: Show ValueType where
  show = genericShow

instance eqValueType :: Eq ValueType where
  eq = genericEq

instance ordValueType :: Ord ValueType where
  compare = genericCompare

instance enumValueType :: Enum ValueType where
  succ = genericSucc
  pred = genericPred

instance boundedValueType :: Bounded ValueType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumValueType :: BoundedEnum ValueType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

valueTypes :: Array ValueType
valueTypes = upFromIncluding bottom

data BlockType
  = BaseContractType
  | BoundsType
  | ActionType ActionType
  | ContractType ContractType
  | ObservationType ObservationType
  | ValueType ValueType
  | PayeeType PayeeType
  | PartyType PartyType
  | TokenType TokenType

derive instance genericBlockType :: Generic BlockType _

instance eqBlockType :: Eq BlockType where
  eq = genericEq

instance ordBlockType :: Ord BlockType where
  compare = genericCompare

instance enumBlockType :: Enum BlockType where
  succ = genericSucc
  pred = genericPred

instance boundedBlockType :: Bounded BlockType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumBlockType :: BoundedEnum BlockType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

instance showBlockType :: Show BlockType where
  show BaseContractType = "BaseContractType"
  show BoundsType = "BoundsType"
  show (ContractType c) = show c
  show (ObservationType ot) = show ot
  show (ValueType vt) = show vt
  show (PayeeType pt) = show pt
  show (PartyType pt) = show pt
  show (TokenType tt) = show tt
  show (ActionType at) = show at

contractColour :: String
contractColour = "#a380bc"

boundsColour :: String
boundsColour = "#1a7b84"

actionColour :: String
actionColour = "#e6aa00"

observationColour :: String
observationColour = "#1fc1c3"

valueColour :: String
valueColour = "#eb2256"

payeeColour :: String
payeeColour = "#709cf0"

partyColour :: String
partyColour = "#f69ab2"

tokenColour :: String
tokenColour = "#eb4a22"

blockColour :: BlockType -> String
blockColour BaseContractType = contractColour

blockColour BoundsType = boundsColour

blockColour (ActionType _) = actionColour

blockColour (ContractType _) = contractColour

blockColour (ObservationType _) = observationColour

blockColour (ValueType _) = valueColour

blockColour (PayeeType _) = payeeColour

blockColour (PartyType _) = partyColour

blockColour (TokenType _) = tokenColour

blockDefinitions :: Array BlockDefinition
blockDefinitions = map toDefinition (upFromIncluding bottom)

definitionsMap :: Map String BlockDefinition
definitionsMap = Map.fromFoldable $
  (\def@(BlockDefinition d) -> Tuple d.type def) <$> blockDefinitions

toDefinition :: BlockType -> BlockDefinition
toDefinition BaseContractType =
  BlockDefinition
    $ merge
        { type: show BaseContractType
        , message0: "%1 CONTRACT %2 %3 %4 %5"
        , args0:
            [ DummyRight
            , DummyRight
            , DummyRight
            , Statement
                { name: show BaseContractType
                , check: show BaseContractType
                , align: AlignRight
                }
            , DummyRight
            ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition BoundsType =
  BlockDefinition
    $ merge
        { type: show BoundsType
        , message0: "between %1 and %2"
        , args0:
            [ Number
                { name: "from"
                , value: 1.0
                , min: Nothing
                , max: Nothing
                , precision: Just 1.0
                }
            , Number
                { name: "to"
                , value: 2.0
                , min: Nothing
                , max: Nothing
                , precision: Just 1.0
                }
            ]
        , colour: blockColour BoundsType
        , previousStatement: Just (show BoundsType)
        , nextStatement: Just (show BoundsType)
        , extensions: [ "number_validator" ]
        }
        defaultBlockDefinition

-- Action
toDefinition blockType@(ActionType DepositActionType) =
  BlockDefinition
    $ merge
        { type: show DepositActionType
        , message0:
            "Deposit %1 by %2 the amount of %3 currency %4 into account of %5 continue as %6 %7"
        , args0:
            [ DummyCentre
            , Value { name: "from_party", check: "party", align: AlignRight }
            , Value { name: "value", check: "value", align: AlignRight }
            , Value { name: "token", check: "token", align: AlignRight }
            , Value { name: "party", check: "party", align: AlignRight }
            , DummyLeft
            , Statement
                { name: "contract"
                , check: show BaseContractType
                , align: AlignRight
                }
            ]
        , colour: blockColour blockType
        , previousStatement: Just "ActionType"
        , nextStatement: Just "ActionType"
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition blockType@(ActionType ChoiceActionType) =
  BlockDefinition
    $ merge
        { type: show ChoiceActionType
        , message0:
            "Choice name %1 %2 choice owner %3 choice bounds %4 %5 continue as %6 %7"
        , args0:
            [ Input { name: "choice_name", text: "name", spellcheck: false }
            , DummyLeft
            , Value { name: "party", check: "party", align: AlignRight }
            , DummyLeft
            , Statement
                { name: "bounds", check: show BoundsType, align: AlignRight }
            , DummyLeft
            , Statement
                { name: "contract"
                , check: show BaseContractType
                , align: AlignRight
                }
            ]
        , colour: blockColour blockType
        , previousStatement: Just "ActionType"
        , nextStatement: Just "ActionType"
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition blockType@(ActionType NotifyActionType) =
  BlockDefinition
    $ merge
        { type: show NotifyActionType
        , message0: "Notification of %1 continue as %2 %3"
        , args0:
            [ Value
                { name: "observation", check: "observation", align: AlignRight }
            , DummyLeft
            , Statement
                { name: "contract"
                , check: show BaseContractType
                , align: AlignRight
                }
            ]
        , colour: blockColour blockType
        , previousStatement: Just "ActionType"
        , nextStatement: Just "ActionType"
        , inputsInline: Just false
        }
        defaultBlockDefinition

-- Payee
toDefinition blockType@(PayeeType AccountPayeeType) =
  BlockDefinition
    $ merge
        { type: show AccountPayeeType
        , message0: "Account of %1 %2"
        , args0:
            [ DummyLeft
            , Value { name: "party", check: "party", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "payee"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(PayeeType PartyPayeeType) =
  BlockDefinition
    $ merge
        { type: show PartyPayeeType
        , message0: "Party %1"
        , args0:
            [ Value { name: "party", check: "party", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "payee"
        , inputsInline: Just true
        }
        defaultBlockDefinition

-- Party
toDefinition blockType@(PartyType AddressPartyType) =
  BlockDefinition
    $ merge
        { type: show AddressPartyType
        , message0: "Address %1"
        , args0:
            [ Input
                { name: "address"
                , text:
                    ""
                , spellcheck: false
                }
            ]
        , colour: blockColour blockType
        , output: Just "party"
        , inputsInline: Just true
        }
        defaultBlockDefinition

-- Ada Token type
toDefinition blockType@(TokenType AdaTokenType) =
  BlockDefinition
    $ merge
        { type: show AdaTokenType
        , message0: "ada"
        , args0: []
        , colour: blockColour blockType
        , output: Just "token"
        , inputsInline: Just true
        }
        defaultBlockDefinition

-- Custom Token type
toDefinition blockType@(TokenType CustomTokenType) =
  BlockDefinition
    $ merge
        { type: show CustomTokenType
        , message0: "Token with currency %1 and token name %2"
        , args0:
            [ Input { name: "currency_symbol", text: "", spellcheck: false }
            , Input { name: "token_name", text: "", spellcheck: false }
            ]
        , colour: blockColour blockType
        , output: Just "token"
        , inputsInline: Just true
        , extensions: [ "hash_validator" ]
        }
        defaultBlockDefinition

toDefinition blockType@(PartyType RolePartyType) =
  BlockDefinition
    $ merge
        { type: show RolePartyType
        , message0: "Role %1"
        , args0:
            [ Input { name: "role", text: "role", spellcheck: false }
            ]
        , colour: blockColour blockType
        , output: Just "party"
        , inputsInline: Just true
        }
        defaultBlockDefinition

-- Contracts
toDefinition blockType@(ContractType CloseContractType) =
  BlockDefinition
    $ merge
        { type: show CloseContractType
        , message0: "Close"
        , colour: blockColour blockType
        , previousStatement: Just (show BaseContractType)
        }
        defaultBlockDefinition

toDefinition blockType@(ContractType PayContractType) =
  BlockDefinition
    $ merge
        { type: show PayContractType
        , message0:
            "Pay %1 payee %2 the amount of %3 of currency %4 from account of %5 continue as %6 %7"
        , args0:
            [ DummyCentre
            , Value { name: "payee", check: "payee", align: AlignRight }
            , Value { name: "value", check: "value", align: AlignRight }
            , Value { name: "token", check: "token", align: AlignRight }
            , Value { name: "party", check: "party", align: AlignRight }
            , DummyLeft
            , Statement
                { name: "contract"
                , check: show BaseContractType
                , align: AlignRight
                }
            ]
        , colour: blockColour blockType
        , previousStatement: Just (show BaseContractType)
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition blockType@(ContractType IfContractType) =
  BlockDefinition
    $ merge
        { type: show IfContractType
        , message0: "If observation %1 then %2 %3 else %4 %5"
        , args0:
            [ Value
                { name: "observation"
                , check: "observation"
                , align:
                    AlignRight
                }
            , DummyLeft
            , Statement
                { name: "contract1"
                , check: show BaseContractType
                , align: AlignRight
                }
            , DummyLeft
            , Statement
                { name: "contract2"
                , check: show BaseContractType
                , align: AlignRight
                }
            ]
        , colour: blockColour blockType
        , previousStatement: Just $ show BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition blockType@(ContractType WhenContractType) =
  BlockDefinition
    $ merge
        { type: show WhenContractType
        , message0: "When %1 %2 after %3 %4 %5 continue as %6 %7"
        , args0:
            [ DummyCentre
            , Statement { name: "case", check: "ActionType", align: AlignLeft }
            , Dropdown
                { name: "timeout_type"
                , options:
                    [ Pair "constant timeout" "time"
                    , Pair "parameterized timeout" "time_param"
                    ]
                }
            , Input { name: "timeout", text: "param", spellcheck: false }
            , DummyLeft
            , DummyLeft
            , Statement
                { name: "contract"
                , check: show BaseContractType
                , align: AlignRight
                }

            ]
        , colour: blockColour blockType
        , previousStatement: Just (show BaseContractType)
        , inputsInline: Just false
        , extensions: [ "dynamic_timeout_type" ]

        }
        defaultBlockDefinition

toDefinition blockType@(ContractType LetContractType) =
  BlockDefinition
    $ merge
        { type: show LetContractType
        , message0: "Let %1 be %2 continue as %3 %4"
        , args0:
            [ Input { name: "value_id", text: "value", spellcheck: false }
            , Value { name: "value", check: "value", align: AlignRight }
            , DummyLeft
            , Statement
                { name: "contract"
                , check: show BaseContractType
                , align: AlignRight
                }
            ]
        , colour: blockColour blockType
        , previousStatement: Just (show BaseContractType)
        }
        defaultBlockDefinition

toDefinition blockType@(ContractType AssertContractType) =
  BlockDefinition
    $ merge
        { type: show AssertContractType
        , message0: "Assert %1 check that %2 continue as %3 %4"
        , args0:
            [ DummyCentre
            , Value
                { name: "observation"
                , check: "observation"
                , align:
                    AlignRight
                }
            , DummyLeft
            , Statement
                { name: "contract"
                , check: show BaseContractType
                , align: AlignRight
                }
            ]
        , colour: blockColour blockType
        , previousStatement: Just (show BaseContractType)
        , inputsInline: Just false
        }
        defaultBlockDefinition

-- Observations
toDefinition blockType@(ObservationType AndObservationType) =
  BlockDefinition
    $ merge
        { type: show AndObservationType
        , message0: "%1 and %2"
        , args0:
            [ Value
                { name: "observation1"
                , check: "observation"
                , align:
                    AlignRight
                }
            , Value
                { name: "observation2"
                , check: "observation"
                , align:
                    AlignRight
                }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType OrObservationType) =
  BlockDefinition
    $ merge
        { type: show OrObservationType
        , message0: "%1 or %2"
        , args0:
            [ Value
                { name: "observation1"
                , check: "observation"
                , align:
                    AlignRight
                }
            , Value
                { name: "observation2"
                , check: "observation"
                , align:
                    AlignRight
                }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType NotObservationType) =
  BlockDefinition
    $ merge
        { type: show NotObservationType
        , message0: "not %1"
        , args0:
            [ Value
                { name: "observation"
                , check: "observation"
                , align:
                    AlignRight
                }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType ChoseSomethingObservationType) =
  BlockDefinition
    $ merge
        { type: show ChoseSomethingObservationType
        , message0: "party %1 made choice %2"
        , args0:
            [ Value { name: "party", check: "party", align: AlignRight }
            , Input { name: "choice_name", text: "name", spellcheck: false }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType ValueGEObservationType) =
  BlockDefinition
    $ merge
        { type: show ValueGEObservationType
        , message0: "value %1 is greater than or equal to %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType ValueGTObservationType) =
  BlockDefinition
    $ merge
        { type: show ValueGTObservationType
        , message0: "value %1 is greater than %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType ValueLEObservationType) =
  BlockDefinition
    $ merge
        { type: show ValueLEObservationType
        , message0: "value %1 is less than or equal to %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType ValueLTObservationType) =
  BlockDefinition
    $ merge
        { type: show ValueLTObservationType
        , message0: "value %1 is less than %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType ValueEQObservationType) =
  BlockDefinition
    $ merge
        { type: show ValueEQObservationType
        , message0: "value %1 is equal to %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType TrueObservationType) =
  BlockDefinition
    $ merge
        { type: show TrueObservationType
        , message0: "true"
        , lastDummyAlign0: AlignCentre
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ObservationType FalseObservationType) =
  BlockDefinition
    $ merge
        { type: show FalseObservationType
        , message0: "false"
        , lastDummyAlign0: AlignCentre
        , colour: blockColour blockType
        , output: Just "observation"
        , inputsInline: Just true
        }
        defaultBlockDefinition

-- Values
toDefinition blockType@(ValueType AvailableMoneyValueType) =
  BlockDefinition
    $ merge
        { type: show AvailableMoneyValueType
        , message0: "Available currency %1 from account of %2 %3 %4 %5"
        , args0:
            [ Value { name: "token", check: "token", align: AlignRight }
            , DummyRight
            , DummyRight
            , Value { name: "party", check: "party", align: AlignRight }
            , DummyRight
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType ConstantValueType) =
  BlockDefinition
    $ merge
        { type: show ConstantValueType
        , message0: "Constant %1"
        , args0:
            [ Number
                { name: "constant"
                , value: 1.0
                , min: Nothing
                , max: Nothing
                , precision: Just 1.0
                }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        , extensions: [ "number_validator" ]
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType ConstantParamValueType) =
  BlockDefinition
    $ merge
        { type: show ConstantParamValueType
        , message0: "ConstantParam %1"
        , args0:
            [ Input
                { name: "paramName", text: "parameterName", spellcheck: false }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType NegValueValueType) =
  BlockDefinition
    $ merge
        { type: show NegValueValueType
        , message0: "- %1"
        , args0:
            [ Value { name: "value", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType AddValueValueType) =
  BlockDefinition
    $ merge
        { type: show AddValueValueType
        , message0: "%1 + %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType MulValueValueType) =
  BlockDefinition
    $ merge
        { type: show MulValueValueType
        , message0: "%1 * %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType DivValueValueType) =
  BlockDefinition
    $ merge
        { type: show DivValueValueType
        , message0: "%1 / %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType CondObservationValueValueType) =
  BlockDefinition
    $ merge
        { type: show CondObservationValueValueType
        , message0: "if %1 then %2 else %3"
        , args0:
            [ Value
                { name: "condition"
                , check: "observation"
                , align:
                    AlignRight
                }
            , Value { name: "then", check: "value", align: AlignRight }
            , Value { name: "else", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType SubValueValueType) =
  BlockDefinition
    $ merge
        { type: show SubValueValueType
        , message0: "%1 - %2"
        , args0:
            [ Value { name: "value1", check: "value", align: AlignRight }
            , Value { name: "value2", check: "value", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType ChoiceValueValueType) =
  BlockDefinition
    $ merge
        { type: show ChoiceValueValueType
        , message0: "Choice %1 by %2"
        , args0:
            [ Input { name: "choice_name", text: "name", spellcheck: false }
            , Value { name: "party", check: "party", align: AlignRight }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType TimeIntervalStartValueType) =
  BlockDefinition
    $ merge
        { type: show TimeIntervalStartValueType
        , message0: "Time Interval Start"
        , lastDummyAlign0: AlignCentre
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType TimeIntervalEndValueType) =
  BlockDefinition
    $ merge
        { type: show TimeIntervalEndValueType
        , message0: "Time Interval End"
        , lastDummyAlign0: AlignCentre
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

toDefinition blockType@(ValueType UseValueValueType) =
  BlockDefinition
    $ merge
        { type: show UseValueValueType
        , message0: "Use name %1"
        , args0:
            [ Input { name: "value_id", text: "value", spellcheck: false }
            ]
        , colour: blockColour blockType
        , output: Just "value"
        , inputsInline: Just true
        }
        defaultBlockDefinition

---------------------------------------------------------------------------------------------------
--
-- Toolbox definition
--
contractsCategory :: Category
contractsCategory = category "Contracts" contractColour $ map (leaf <<< show)
  contractTypes

observationsCategory :: Category
observationsCategory = category "Observations" observationColour $ map
  (leaf <<< show)
  observationTypes

actionsCategory :: Category
actionsCategory = category "Actions" actionColour $ map (leaf <<< show)
  actionTypes

valueCategory :: Category
valueCategory = category "Values" valueColour $ map (leaf <<< show) valueTypes

payeeCategory :: Category
payeeCategory = category "Payee" payeeColour $ map (leaf <<< show) payeeTypes

partyCategory :: Category
partyCategory = category "Party" partyColour $ map (leaf <<< show) partyTypes

tokenCategory :: Category
tokenCategory = category "Token" tokenColour $ map (leaf <<< show) tokenTypes

boundsCategory :: Category
boundsCategory = category "Bounds" boundsColour [ leaf $ show BoundsType ]

-- This map ties a block definition "check" with a Category that can be displayed in the Toolbar
-- as part of the Blockly holes functionality.
-- TODO: We should probably stop relying on `Show` for check and use a NewType to avoid having any string
typeMap :: Map String Category
typeMap =
  Map.fromFoldable
    [ Tuple (show BaseContractType) contractsCategory
    , Tuple "ActionType" actionsCategory
    , Tuple "observation" observationsCategory
    , Tuple "value" valueCategory
    , Tuple "payee" payeeCategory
    , Tuple "party" partyCategory
    , Tuple "token" tokenCategory
    , Tuple (show BoundsType) boundsCategory
    ]

defaultCategories :: Array Category
defaultCategories =
  [ contractsCategory
  , observationsCategory
  , actionsCategory
  , valueCategory
  , payeeCategory
  , partyCategory
  , tokenCategory
  , boundsCategory
  ]

toolbox :: Toolbox
toolbox = CategoryToolbox defaultCategories

toolboxWithHoles :: BlockDefinition -> Toolbox
toolboxWithHoles definition = CategoryToolbox
  (defaultCategories <> addSeparator holesCategories)
  where
  addSeparator = case _ of
    [] -> []
    xs -> [ separator ] <> xs

  holesCategories :: Array Category
  holesCategories =
    catMaybes
      $ typedArguments definition
          <#> \{ name, check } -> rename name <$> Map.lookup check typeMap

---------------------------------------------------------------------------------------------------
--
-- Code generation
--
blockToContract :: BDom.Block -> Either String (Term Contract)
blockToContract block = lmap explainParseTermError $ blockToTerm block

class BlockToTerm a where
  blockToTerm
    :: forall m. MonadError ParseTermError m => BDom.Block -> m (Term a)

data ParseTermError
  = InvalidBlock BDom.Block String
  | MissingArgument BDom.Block String
  | InvalidChildType String
  | InvalidFieldCast String String
  | ErrorInChild BDom.Block String ParseTermError

explainParseTermError :: ParseTermError -> String
explainParseTermError (InvalidBlock block expectedType) = "Block with id "
  <> show block.id
  <> " and type "
  <> show block.type
  <> " is not a valid "
  <> expectedType
  <> " type"

explainParseTermError (MissingArgument block attr) = "Block " <> show block.id
  <> " is missing required argument "
  <> show attr

explainParseTermError (InvalidChildType childType) =
  "Attribute should be of type " <> childType

explainParseTermError (InvalidFieldCast fieldValue castType) =
  "Could not convert value " <> show fieldValue <> " to " <> castType

explainParseTermError (ErrorInChild block attr err) = "Error in " <> block.type
  <> "."
  <> attr
  <> explainNested err
  where
  explainNested (ErrorInChild block' attr' err') = " -> " <> block'.type <> "."
    <> attr'
    <> explainNested err'

  explainNested err' = ": " <> explainParseTermError err'

getRequiredAttribute
  :: forall m
   . MonadThrow ParseTermError m
  => String
  -> BDom.Block
  -> m BDom.BlockChild
getRequiredAttribute attr block = case (Object.lookup attr block.children) of
  Nothing -> throwError $ MissingArgument block attr
  Just child -> pure child

asStatement
  :: forall m
   . MonadThrow ParseTermError m
  => BDom.BlockChild
  -> m (Array BDom.Block)
asStatement child = case child of
  BDom.Statement blocks -> pure blocks
  _ -> throwError $ InvalidChildType "Statement"

asSingleStatement
  :: forall m. MonadThrow ParseTermError m => BDom.BlockChild -> m BDom.Block
asSingleStatement child = do
  statements <- asStatement child
  case uncons statements of
    Just { head, tail: [] } -> pure head
    _ -> throwError $ InvalidChildType "Statement with a single child"

asValue
  :: forall m. MonadThrow ParseTermError m => BDom.BlockChild -> m BDom.Block
asValue child = case child of
  BDom.Value block -> pure block
  _ -> throwError $ InvalidChildType "Value"

asField :: forall m. MonadThrow ParseTermError m => BDom.BlockChild -> m String
asField child = case child of
  BDom.Field text -> pure text
  _ -> throwError $ InvalidChildType "Field"

asBigInt :: forall m. MonadThrow ParseTermError m => String -> m BigInt
asBigInt str = toMonadThrow $ note' (\_ -> InvalidFieldCast str "BigInt")
  (BigInt.fromString str)

mkTermFromChild
  :: forall m a
   . MonadError ParseTermError m
  => BlockToTerm a
  => (BDom.BlockChild -> m BDom.Block)
  -> String
  -> BDom.Block
  -> m (Term a)
mkTermFromChild childToBlock attr block =
  case Object.lookup attr block.children of
    -- FIXME: Check if I can use something relating to the term type `a` instead of
    --        attr to generate the hole name. That way I could rename the blockly attributes
    --        without problem
    Nothing -> pure $ Hole attr (BlockId block.id)
    Just child ->
      catchError
        (blockToTerm =<< childToBlock child)
        (\err -> throwError $ ErrorInChild block attr err)

valueToTerm
  :: forall m a
   . MonadError ParseTermError m
  => BlockToTerm a
  => String
  -> BDom.Block
  -> m (Term a)
valueToTerm = mkTermFromChild asValue

singleStatementToTerm
  :: forall m a
   . MonadError ParseTermError m
  => BlockToTerm a
  => String
  -> BDom.Block
  -> m (Term a)
singleStatementToTerm = mkTermFromChild asSingleStatement

-- Parse the child of a block as a statement (array of blocks), and convert each
-- block to a term
statementsToTerms
  :: forall m a
   . MonadError ParseTermError m
  => BlockToTerm a
  => String
  -> BDom.Block
  -> m (Array (Term a))
statementsToTerms attr block =
  let
    parseStatements child = do
      statements <- catchError (asStatement child)
        (\err -> throwError $ ErrorInChild block attr err)
      forWithIndex statements \i block' ->
        catchError
          (blockToTerm block')
          ( \err -> throwError $ ErrorInChild block
              (attr <> "[" <> show i <> "]")
              err
          )
  in
    maybe
      (pure [])
      parseStatements
      (Object.lookup attr block.children)

fieldAsString
  :: forall m
   . MonadError ParseTermError m
  => String
  -> BDom.Block
  -> m String
fieldAsString attr block =
  catchError
    (asField =<< getRequiredAttribute attr block)
    (\err -> throwError $ ErrorInChild block attr err)

fieldAsInstant
  :: forall m
   . MonadError ParseTermError m
  => String
  -> BDom.Block
  -> m Instant
fieldAsInstant attr block = do
  bigIntVal <- fieldAsBigInt attr block
  case bigIntToInstant bigIntVal of
    Nothing -> throwError $ ErrorInChild block attr $
      InvalidFieldCast (BigInt.toString bigIntVal) "POSIXTime"
    Just time -> pure time

fieldAsBigInt
  :: forall m
   . MonadError ParseTermError m
  => String
  -> BDom.Block
  -> m BigInt
fieldAsBigInt attr block =
  catchError
    (asBigInt =<< asField =<< getRequiredAttribute attr block)
    (\err -> throwError $ ErrorInChild block attr err)

instance blockToTermContract :: BlockToTerm Contract where
  blockToTerm { type: "BaseContractType", children, id } =
    case Object.lookup "BaseContractType" children of
      Nothing -> pure $ Hole "contract" (BlockId id)
      Just child -> blockToTerm =<< asSingleStatement child
  blockToTerm { type: "CloseContractType", id } = pure $ Term Close (BlockId id)
  blockToTerm b@({ type: "PayContractType", id }) = do
    accountOwner <- valueToTerm "party" b
    payee <- valueToTerm "payee" b
    token <- valueToTerm "token" b
    value <- valueToTerm "value" b
    contract <- singleStatementToTerm "contract" b
    pure $ Term (Pay accountOwner payee token value contract) (BlockId id)
  blockToTerm b@({ type: "IfContractType", id }) = do
    observation <- valueToTerm "observation" b
    contract1 <- singleStatementToTerm "contract1" b
    contract2 <- singleStatementToTerm "contract2" b
    pure $ Term (If observation contract1 contract2) (BlockId id)
  blockToTerm b@({ type: "WhenContractType", id }) = do
    timeoutType <- fieldAsString "timeout_type" b
    cases <- statementsToTerms "case" b
    let
      location = (BlockId id)
    timeout <- case timeoutType of
      "time" -> do
        time <- fieldAsInstant "timeout" b
        pure $ Term (TimeValue time) location
      "time_param" -> do
        timeParam <- fieldAsString "timeout" b
        pure $ Term (TimeParam timeParam) location
      _ -> throwError $ ErrorInChild b "timeout_type"
        (InvalidChildType "Timeout")
    contract <- singleStatementToTerm "contract" b
    pure $ Term (When cases timeout contract) location
  blockToTerm b@({ type: "LetContractType", id }) = do
    valueId <- fieldAsString "value_id" b
    value <- valueToTerm "value" b
    contract <- singleStatementToTerm "contract" b
    let
      location = (BlockId id)

      valueIdTerm = (TermWrapper (ValueId valueId) location)
    pure $ Term (Let valueIdTerm value contract) location
  blockToTerm b@({ type: "AssertContractType", id }) = do
    contract <- singleStatementToTerm "contract" b
    observation <- valueToTerm "observation" b
    pure $ Term (Assert observation contract) (BlockId id)
  blockToTerm block = throwError $ InvalidBlock block "Contract"

instance blockToTermObservation :: BlockToTerm Observation where
  blockToTerm b@({ type: "AndObservationType", id }) = do
    observation1 <- valueToTerm "observation1" b
    observation2 <- valueToTerm "observation2" b
    pure $ Term (AndObs observation1 observation2) (BlockId id)
  blockToTerm b@({ type: "OrObservationType", id }) = do
    observation1 <- valueToTerm "observation1" b
    observation2 <- valueToTerm "observation2" b
    pure $ Term (OrObs observation1 observation2) (BlockId id)
  blockToTerm b@({ type: "NotObservationType", id }) = do
    observation <- valueToTerm "observation" b
    pure $ Term (NotObs observation) (BlockId id)
  blockToTerm b@({ type: "ChoseSomethingObservationType", id }) = do
    party <- valueToTerm "party" b
    choiceName <- fieldAsString "choice_name" b
    let
      choice = ChoiceId choiceName party
    pure $ Term (ChoseSomething choice) (BlockId id)
  blockToTerm b@({ type: "ValueGEObservationType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (ValueGE value1 value2) (BlockId id)
  blockToTerm b@({ type: "ValueGTObservationType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (ValueGT value1 value2) (BlockId id)
  blockToTerm b@({ type: "ValueLTObservationType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (ValueLT value1 value2) (BlockId id)
  blockToTerm b@({ type: "ValueLEObservationType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (ValueLE value1 value2) (BlockId id)
  blockToTerm b@({ type: "ValueEQObservationType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (ValueEQ value1 value2) (BlockId id)
  blockToTerm { type: "TrueObservationType", id } = pure $ Term TrueObs
    (BlockId id)
  blockToTerm { type: "FalseObservationType", id } = pure $ Term FalseObs
    (BlockId id)
  blockToTerm block = throwError $ InvalidBlock block "Observation"

instance blockToTermValue :: BlockToTerm Value where
  blockToTerm b@({ type: "AvailableMoneyValueType", id }) = do
    party <- valueToTerm "party" b
    token <- valueToTerm "token" b
    pure $ Term (AvailableMoney party token) (BlockId id)
  blockToTerm b@({ type: "ConstantValueType", id }) = do
    constant <- fieldAsBigInt "constant" b
    pure $ Term (Constant constant) (BlockId id)
  blockToTerm b@({ type: "ConstantParamValueType", id }) = do
    paramName <- fieldAsString "paramName" b
    pure $ Term (ConstantParam paramName) (BlockId id)
  blockToTerm b@({ type: "NegValueValueType", id }) = do
    value <- valueToTerm "value" b
    pure $ Term (NegValue value) (BlockId id)
  blockToTerm b@({ type: "AddValueValueType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (AddValue value1 value2) (BlockId id)
  blockToTerm b@({ type: "SubValueValueType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (SubValue value1 value2) (BlockId id)
  blockToTerm b@({ type: "MulValueValueType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (MulValue value1 value2) (BlockId id)
  blockToTerm b@({ type: "DivValueValueType", id }) = do
    value1 <- valueToTerm "value1" b
    value2 <- valueToTerm "value2" b
    pure $ Term (DivValue value1 value2) (BlockId id)
  blockToTerm b@({ type: "ChoiceValueValueType", id }) = do
    choiceName <- fieldAsString "choice_name" b
    party <- valueToTerm "party" b
    pure $ Term (ChoiceValue (ChoiceId choiceName party)) (BlockId id)
  blockToTerm ({ type: "TimeIntervalStartValueType", id }) = pure $ Term
    TimeIntervalStart
    (BlockId id)
  blockToTerm ({ type: "TimeIntervalEndValueType", id }) = pure $ Term
    TimeIntervalEnd
    (BlockId id)
  blockToTerm b@({ type: "UseValueValueType", id }) = do
    valueId <- fieldAsString "value_id" b
    let
      location = (BlockId id)

      value = TermWrapper (ValueId valueId) location
    pure $ Term (UseValue value) location
  blockToTerm b@({ type: "CondObservationValueValueType", id }) = do
    condition <- valueToTerm "condition" b
    thenVal <- valueToTerm "then" b
    elseVal <- valueToTerm "else" b
    pure $ Term (Cond condition thenVal elseVal) (BlockId id)
  blockToTerm block = throwError $ InvalidBlock block "Value"

instance blockToTermCase :: BlockToTerm Case where
  blockToTerm b@({ type: "DepositActionType", id }) = do
    by <- valueToTerm "from_party" b
    intoAccountOf <- valueToTerm "party" b
    token <- valueToTerm "token" b
    value <- valueToTerm "value" b
    contract <- singleStatementToTerm "contract" b
    let
      location = (BlockId id)

      action = Term (Deposit intoAccountOf by token value) location
    pure $ Term (Case action contract) location
  blockToTerm b@({ type: "ChoiceActionType", id }) = do
    choiceName <- fieldAsString "choice_name" b
    party <- valueToTerm "party" b
    bounds <- statementsToTerms "bounds" b
    contract <- singleStatementToTerm "contract" b
    let
      location = (BlockId id)

      choice = ChoiceId choiceName party

      action = Term (Choice choice bounds) location
    pure $ Term (Case action contract) location
  blockToTerm b@({ type: "NotifyActionType", id }) = do
    observation <- valueToTerm "observation" b
    contract <- singleStatementToTerm "contract" b
    let
      location = (BlockId id)

      action = Term (Notify observation) location
    pure $ Term (Case action contract) location
  blockToTerm block = throwError $ InvalidBlock block "Action"

instance blockToTermParty :: BlockToTerm Party where
  blockToTerm b@({ type: "AddressPartyType", id }) = do
    address <- fieldAsString "address" b
    pure $ Term (Address address) (BlockId id)
  blockToTerm b@({ type: "RolePartyType", id }) = do
    role <- fieldAsString "role" b
    pure $ Term (Role role) (BlockId id)
  blockToTerm block = throwError $ InvalidBlock block "Party"

instance blockToTermPayee :: BlockToTerm Payee where
  blockToTerm b@({ type: "AccountPayeeType", id }) = do
    party <- valueToTerm "party" b
    pure $ Term (Account party) (BlockId id)
  blockToTerm b@({ type: "PartyPayeeType", id }) = do
    party <- valueToTerm "party" b
    pure $ Term (Party party) (BlockId id)
  blockToTerm block = throwError $ InvalidBlock block "Payee"

instance blockToTermToken :: BlockToTerm Token where
  blockToTerm ({ type: "AdaTokenType", id }) = pure $ Term (Token "" "")
    (BlockId id)
  blockToTerm b@({ type: "CustomTokenType", id }) = do
    currencySymbol <- fieldAsString "currency_symbol" b
    tokenName <- fieldAsString "token_name" b
    pure $ Term (Token currencySymbol tokenName) (BlockId id)
  blockToTerm block = throwError $ InvalidBlock block "Token"

instance blockToTermBound :: BlockToTerm Bound where
  blockToTerm b@({ type: "BoundsType", id }) = do
    from <- fieldAsBigInt "from" b
    to <- fieldAsBigInt "to" b
    pure $ Term (Bound from to) (BlockId id)
  blockToTerm block = throwError $ InvalidBlock block "Bound"

---------------------------------------------------------------------------------------------------
buildBlocks :: NewBlockFunction -> BlocklyState -> Term Contract -> Effect Unit
buildBlocks newBlock bs contract = do
  clearWorkspace bs.workspace
  initializeWorkspace bs
  -- Get or create rootBlock
  mRootBlock <- getBlockById bs.workspace bs.rootBlockName
  rootBlock <- case mRootBlock of
    Nothing -> newBlock bs.workspace (show BaseContractType)
    Just block -> pure block
  let
    mInput = getInputWithName (show BaseContractType) $ inputList rootBlock
  for_ mInput \input -> do
    toBlockly newBlock bs.workspace input contract
    render bs.workspace
  -- We clear the UNDO stack so that we can't delete the base contract with that action.
  clearUndoStack bs.workspace

setField :: Block -> String -> String -> Effect Unit
setField block name value = do
  let
    fields = inputList block >>= fieldRow
  case Array.find (\f -> fieldName f == name) fields of
    Nothing -> pure unit
    Just field -> setFieldText field value

getNextInput :: Block -> Effect (Maybe Input)
getNextInput block = do
  let
    inputs = inputList block

    nextConInputs = filter (\input -> inputType input == 5) inputs
  pure (head nextConInputs)

inputToBlockly
  :: forall a
   . ToBlockly a
  => NewBlockFunction
  -> Workspace
  -> Block
  -> String
  -> a
  -> Effect Unit
inputToBlockly newBlock workspace block name value = do
  case Array.find (\i -> inputName i == name) (inputList block) of
    Nothing -> pure unit
    Just input -> toBlockly newBlock workspace input value

class ToBlockly a where
  toBlockly :: NewBlockFunction -> Workspace -> Input -> a -> Effect Unit

instance toBlocklyTerm :: ToBlockly a => ToBlockly (Term a) where
  toBlockly newBlock workspace input (Term a _) = toBlockly newBlock workspace
    input
    a
  toBlockly _ _ _ _ = pure unit

instance toBlocklyPayee :: ToBlockly Payee where
  toBlockly newBlock workspace input (Account accountOwner) = do
    block <- newBlock workspace (show AccountPayeeType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "party" accountOwner
  toBlockly newBlock workspace input (Party party) = do
    block <- newBlock workspace (show PartyPayeeType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "party" party

instance toBlocklyParty :: ToBlockly Party where
  toBlockly newBlock workspace input (Address address) = do
    block <- newBlock workspace (show AddressPartyType)
    connectToOutput block input
    setField block "address" address
  toBlockly newBlock workspace input (Role role) = do
    block <- newBlock workspace (show RolePartyType)
    connectToOutput block input
    setField block "role" role

instance toBlocklyToken :: ToBlockly Token where
  toBlockly newBlock workspace input (Token "" "") = do
    block <- newBlock workspace (show AdaTokenType)
    connectToOutput block input
  toBlockly newBlock workspace input (Token currSym tokName) = do
    block <- newBlock workspace (show CustomTokenType)
    connectToOutput block input
    setField block "currency_symbol" currSym
    setField block "token_name" tokName

nextBound
  :: NewBlockFunction
  -> Workspace
  -> Connection
  -> Array (Term Bound)
  -> Effect Unit
nextBound newBlock workspace fromConnection bounds = do
  case uncons bounds of
    Nothing -> pure unit
    Just { head: (Hole _ _) } -> pure unit
    Just { head: (Term (Bound from to) _), tail } -> do
      block <- newBlock workspace (show BoundsType)
      setField block "from" (BigInt.toString from)
      setField block "to" (BigInt.toString to)
      let
        toConnection = previousConnection block
      connect fromConnection toConnection
      let
        nextFromConnection = nextConnection block
      nextBound newBlock workspace nextFromConnection tail

instance toBlocklyBounds :: ToBlockly (Array (Term Bound)) where
  toBlockly newBlock workspace input bounds = do
    case uncons bounds of
      Nothing -> pure unit
      Just { head: (Hole _ _) } -> pure unit
      Just { head: (Term (Bound from to) _), tail } -> do
        block <- newBlock workspace (show BoundsType)
        setField block "from" (BigInt.toString from)
        setField block "to" (BigInt.toString to)
        connectToPrevious block input
        let
          fromConnection = nextConnection block
        nextBound newBlock workspace fromConnection tail

oneCaseToBlockly :: NewBlockFunction -> Workspace -> Case -> Effect Block
oneCaseToBlockly
  newBlock
  workspace
  (Case (Term (Deposit accountOwner party tok value) _) cont) = do
  block <- newBlock workspace (show DepositActionType)
  inputToBlockly newBlock workspace block "party" accountOwner
  inputToBlockly newBlock workspace block "token" tok
  inputToBlockly newBlock workspace block "from_party" party
  inputToBlockly newBlock workspace block "value" value
  inputToBlockly newBlock workspace block "contract" cont
  pure block

oneCaseToBlockly
  newBlock
  workspace
  (Case (Term (Choice (ChoiceId choiceName choiceOwner) bounds) _) cont) = do
  block <- newBlock workspace (show ChoiceActionType)
  setField block "choice_name" choiceName
  inputToBlockly newBlock workspace block "party" choiceOwner
  inputToBlockly newBlock workspace block "bounds" bounds
  inputToBlockly newBlock workspace block "contract" cont
  pure block

oneCaseToBlockly newBlock workspace (Case (Term (Notify observation) _) cont) =
  do
    block <- newBlock workspace (show NotifyActionType)
    inputToBlockly newBlock workspace block "observation" observation
    inputToBlockly newBlock workspace block "contract" cont
    pure block

-- This is a temporary hack to cover a mismatch between blockly and holes
-- Case is a pair of an Action and a Contract so to make code easy to write in the simulation
-- we allow `Case ?action ?contract` however that doesn't fit in with Blockly which doesn't
-- have a `Case` block type but instead flattens things out. So in the case of `Case ?action ?contract`
-- we will allow blockly to fill in a default Notify action
oneCaseToBlockly newBlock workspace _ = newBlock workspace
  (show NotifyActionType)

nextCase
  :: NewBlockFunction
  -> Workspace
  -> Connection
  -> Array (Term Case)
  -> Effect Unit
nextCase newBlock workspace fromConnection cases = do
  case uncons cases of
    Nothing -> pure unit
    Just { head: (Hole _ _) } -> pure unit
    Just { head: (Term (Case action contract) _), tail } -> do
      block <- oneCaseToBlockly newBlock workspace (Case action contract)
      let
        toConnection = previousConnection block
      connect fromConnection toConnection
      let
        nextFromConnection = nextConnection block
      nextCase newBlock workspace nextFromConnection tail

instance toBlocklyCases :: ToBlockly (Array (Term Case)) where
  toBlockly newBlock workspace input cases = do
    case uncons cases of
      Nothing -> pure unit
      Just { head: (Hole _ _) } -> pure unit
      Just { head: (Term (Case action contract) _), tail } -> do
        block <- oneCaseToBlockly newBlock workspace (Case action contract)
        connectToPrevious block input
        let
          fromConnection = nextConnection block
        nextCase newBlock workspace fromConnection tail

instance toBlocklyContract :: ToBlockly Contract where
  toBlockly newBlock workspace input Close = do
    block <- newBlock workspace (show CloseContractType)
    connectToPrevious block input
  toBlockly newBlock workspace input (Pay accountOwner payee tok value contract) =
    do
      block <- newBlock workspace (show PayContractType)
      connectToPrevious block input
      inputToBlockly newBlock workspace block "party" accountOwner
      inputToBlockly newBlock workspace block "token" tok
      inputToBlockly newBlock workspace block "payee" payee
      inputToBlockly newBlock workspace block "value" value
      inputToBlockly newBlock workspace block "contract" contract
  toBlockly newBlock workspace input (If observation contract1 contract2) = do
    block <- newBlock workspace (show IfContractType)
    connectToPrevious block input
    inputToBlockly newBlock workspace block "observation" observation
    inputToBlockly newBlock workspace block "contract1" contract1
    inputToBlockly newBlock workspace block "contract2" contract2
  toBlockly newBlock workspace input (When cases timeout contract) = do
    block <- newBlock workspace (show WhenContractType)
    connectToPrevious block input
    inputToBlockly newBlock workspace block "case" cases
    setField block "timeout_type"
      ( case timeout of
          Term (TimeParam _) _ -> "time_param"
          _ -> "time"
      )
    setField block "timeout"
      ( case timeout of
          Term (TimeValue time) _ ->
            BigInt.toString $ instantToBigInt time
          Term (TimeParam paramName) _ -> paramName
          _ -> "0"
      )
    inputToBlockly newBlock workspace block "contract" contract
  toBlockly
    newBlock
    workspace
    input
    (Let (TermWrapper (ValueId valueId) _) value contract) = do
    block <- newBlock workspace (show LetContractType)
    connectToPrevious block input
    setField block "value_id" valueId
    inputToBlockly newBlock workspace block "value" value
    inputToBlockly newBlock workspace block "contract" contract
  toBlockly newBlock workspace input (Assert observation contract) = do
    block <- newBlock workspace (show AssertContractType)
    connectToPrevious block input
    inputToBlockly newBlock workspace block "observation" observation
    inputToBlockly newBlock workspace block "contract" contract

instance toBlocklyObservation :: ToBlockly Observation where
  toBlockly newBlock workspace input (AndObs observation1 observation2) = do
    block <- newBlock workspace (show AndObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "observation1" observation1
    inputToBlockly newBlock workspace block "observation2" observation2
  toBlockly newBlock workspace input (OrObs observation1 observation2) = do
    block <- newBlock workspace (show OrObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "observation1" observation1
    inputToBlockly newBlock workspace block "observation2" observation2
  toBlockly newBlock workspace input (NotObs observation) = do
    block <- newBlock workspace (show NotObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "observation" observation
  toBlockly
    newBlock
    workspace
    input
    (ChoseSomething (ChoiceId choiceName choiceOwner)) = do
    block <- newBlock workspace (show ChoseSomethingObservationType)
    connectToOutput block input
    setField block "choice_name" choiceName
    inputToBlockly newBlock workspace block "party" choiceOwner
  toBlockly newBlock workspace input (ValueGE v1 v2) = do
    block <- newBlock workspace (show ValueGEObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input (ValueGT v1 v2) = do
    block <- newBlock workspace (show ValueGTObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input (ValueLT v1 v2) = do
    block <- newBlock workspace (show ValueLTObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input (ValueLE v1 v2) = do
    block <- newBlock workspace (show ValueLEObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input (ValueEQ v1 v2) = do
    block <- newBlock workspace (show ValueEQObservationType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input TrueObs = do
    block <- newBlock workspace (show TrueObservationType)
    connectToOutput block input
  toBlockly newBlock workspace input FalseObs = do
    block <- newBlock workspace (show FalseObservationType)
    connectToOutput block input

instance toBlocklyValue :: ToBlockly Value where
  toBlockly newBlock workspace input (AvailableMoney accountOwner tok) = do
    block <- newBlock workspace (show AvailableMoneyValueType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "party" accountOwner
    inputToBlockly newBlock workspace block "token" tok
  toBlockly newBlock workspace input (Constant v) = do
    block <- newBlock workspace (show ConstantValueType)
    connectToOutput block input
    setField block "constant" (BigInt.toString v)
  toBlockly newBlock workspace input (ConstantParam n) = do
    block <- newBlock workspace (show ConstantParamValueType)
    connectToOutput block input
    setField block "paramName" n
  toBlockly newBlock workspace input (NegValue v) = do
    block <- newBlock workspace (show NegValueValueType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value" v
  toBlockly newBlock workspace input (AddValue v1 v2) = do
    block <- newBlock workspace (show AddValueValueType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input (SubValue v1 v2) = do
    block <- newBlock workspace (show SubValueValueType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input (MulValue v1 v2) = do
    block <- newBlock workspace (show MulValueValueType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly newBlock workspace input (DivValue v1 v2) = do
    block <- newBlock workspace (show DivValueValueType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "value1" v1
    inputToBlockly newBlock workspace block "value2" v2
  toBlockly
    newBlock
    workspace
    input
    (ChoiceValue (ChoiceId choiceName choiceOwner)) = do
    block <- newBlock workspace (show ChoiceValueValueType)
    connectToOutput block input
    setField block "choice_name" choiceName
    inputToBlockly newBlock workspace block "party" choiceOwner
  toBlockly newBlock workspace input TimeIntervalStart = do
    block <- newBlock workspace (show TimeIntervalStartValueType)
    connectToOutput block input
  toBlockly newBlock workspace input TimeIntervalEnd = do
    block <- newBlock workspace (show TimeIntervalEndValueType)
    connectToOutput block input
  toBlockly
    newBlock
    workspace
    input
    (UseValue (TermWrapper (ValueId valueId) _)) = do
    block <- newBlock workspace (show UseValueValueType)
    connectToOutput block input
    setField block "value_id" valueId
  toBlockly newBlock workspace input (Cond cond thn els) = do
    block <- newBlock workspace (show CondObservationValueValueType)
    connectToOutput block input
    inputToBlockly newBlock workspace block "condition" cond
    inputToBlockly newBlock workspace block "then" thn
    inputToBlockly newBlock workspace block "else" els
