module MainFrame.Types where

import Prologue hiding (div)

import Analytics (class IsEvent, defaultEvent, toEvent)
import Auth (AuthStatus, _GithubUser, authStatusAuthRole)
import Component.Blockly.Types as Blockly
import Component.ConfirmUnsavedNavigation.Types as ConfirmUnsavedNavigation
import Component.CurrencyInput as CurrencyInput
import Component.DateTimeLocalInput.Types as DateTimeLocalInput
import Component.Demos.Types as Demos
import Component.MetadataTab.Types (MetadataAction)
import Component.NewProject.Types as NewProject
import Component.Projects.Types (Lang(..))
import Component.Projects.Types as Projects
import Component.Tooltip.Types (ReferenceId)
import Data.Argonaut (class DecodeJson, class EncodeJson, encodeJson)
import Data.Argonaut.Core (jsonNull)
import Data.Argonaut.Decode ((.:), (.:?))
import Data.Argonaut.Decode.Decoders (decodeJObject)
import Data.Generic.Rep (class Generic)
import Data.Lens (Lens', has, lens, set, view, (^.))
import Data.Lens.Record (prop)
import Data.Maybe (maybe)
import Data.Newtype (class Newtype)
import Data.Show.Generic (genericShow)
import Data.Time.Duration (Minutes)
import Gist (Gist)
import Gists.Extra (GistId)
import Gists.Types (GistAction)
import Halogen (ClassName)
import Halogen as H
import Halogen.Classes (activeClass)
import Halogen.Monaco (KeyBindings)
import Halogen.Monaco as Monaco
import Language.Marlowe.Extended.V1.Metadata.Types (MetaData)
import Network.RemoteData (_Loading, _Success)
import Page.BlocklyEditor.Types as BE
import Page.HaskellEditor.Types as HE
import Page.JavascriptEditor.Types (CompilationState)
import Page.JavascriptEditor.Types as JS
import Page.MarloweEditor.Types as ME
import Page.Simulation.Types as Simulation
import Record (delete, get, insert) as Record
import Rename.Types as Rename
import Router (Route)
import SaveAs.Types as SaveAs
import Type.Proxy (Proxy(..))
import Types (WebData, WebpackBuildMode)
import Web.UIEvent.KeyboardEvent (KeyboardEvent)

data ModalView
  = NewProject
  | OpenProject
  | OpenDemo
  | RenameProject
  | SaveProjectAs
  | GithubLogin Action
  | ConfirmUnsavedNavigation Action

derive instance genericModalView :: Generic ModalView _

instance showModalView :: Show ModalView where
  show NewProject = "NewProject"
  show OpenProject = "OpenProject"
  show OpenDemo = "OpenDemo"
  show RenameProject = "RenameProject"
  show SaveProjectAs = "SaveProjectAs"
  show (ConfirmUnsavedNavigation _) = "ConfirmUnsavedNavigation"
  show (GithubLogin _) = "GithubLogin"

-- Before adding the intended action to GithubLogin, this instance was being
-- handled by the genericShow. Action does not have a show instance so genericShow
-- does not work. For the moment I've made a manual instance, but not sure why
-- ModalView requires show, or if we should make Action an instance of Show
-- show = genericShow
data Query a = ChangeRoute Route a

data Action
  = Init
  | HandleKey H.SubscriptionId KeyboardEvent
  | HaskellAction HE.Action
  | SimulationAction Simulation.Action
  | BlocklyEditorAction BE.Action
  | MarloweEditorAction ME.Action
  | JavascriptAction JS.Action
  | ShowBottomPanel Boolean
  | ChangeView View
  | ConfirmUnsavedNavigationAction Action ConfirmUnsavedNavigation.Action
  | Logout
  -- blockly
  | ProjectsAction Projects.Action
  | NewProjectAction NewProject.Action
  | DemosAction Demos.Action
  | RenameAction Rename.Action
  | SaveAsAction SaveAs.Action
  -- Gist support.
  | CheckAuthStatus
  | GistAction GistAction
  | OpenModal ModalView
  | CloseModal
  | OpenLoginPopup Action

-- | Here we decide which top-level queries to track as GA events, and
-- how to classify them.
instance actionIsEvent :: IsEvent Action where
  toEvent Init = Just $ defaultEvent "Init"
  toEvent (HandleKey _ _) = Just $ defaultEvent "HandleKey"
  toEvent (HaskellAction action) = toEvent action
  toEvent (SimulationAction action) = toEvent action
  toEvent (BlocklyEditorAction action) = toEvent action
  toEvent (JavascriptAction action) = toEvent action
  toEvent (MarloweEditorAction action) = toEvent action
  toEvent (ChangeView view) = Just $ (defaultEvent "View")
    { label = Just (show view) }
  toEvent (ShowBottomPanel _) = Just $ defaultEvent "ShowBottomPanel"
  toEvent (ProjectsAction action) = toEvent action
  toEvent (NewProjectAction action) = toEvent action
  toEvent (DemosAction action) = toEvent action
  toEvent (RenameAction action) = toEvent action
  toEvent (SaveAsAction action) = toEvent action
  toEvent (ConfirmUnsavedNavigationAction _ _) = Just $ defaultEvent
    "ConfirmUnsavedNavigation"
  toEvent CheckAuthStatus = Just $ defaultEvent "CheckAuthStatus"
  toEvent (GistAction _) = Just $ defaultEvent "GistAction"
  toEvent (OpenModal view) = Just $ (defaultEvent (show view))
    { category = Just "OpenModal" }
  toEvent CloseModal = Just $ defaultEvent "CloseModal"
  toEvent (OpenLoginPopup _) = Just $ defaultEvent "OpenLoginPopup"
  toEvent Logout = Just $ defaultEvent "Logout"

data View
  = HomePage
  | MarloweEditor
  | HaskellEditor
  | JSEditor
  | Simulation
  | BlocklyEditor

derive instance eqView :: Eq View

derive instance genericView :: Generic View _

instance showView :: Show View where
  show = genericShow

type ChildSlots =
  ( haskellEditorSlot :: H.Slot Monaco.Query Monaco.Message Unit
  , jsEditorSlot :: H.Slot Monaco.Query Monaco.Message Unit
  , blocklySlot :: H.Slot Blockly.Query Blockly.Message Unit
  , simulationSlot :: H.Slot Simulation.Query Blockly.Message Unit
  , simulatorEditorSlot :: H.Slot Monaco.Query Monaco.Message Unit
  , marloweEditorPageSlot :: H.Slot Monaco.Query Monaco.Message Unit
  , metadata :: forall query. H.Slot query MetadataAction Unit
  , tooltipSlot :: forall query. H.Slot query Void ReferenceId
  , hintSlot :: forall query. H.Slot query Void String
  , currencyInput :: CurrencyInput.Slot String
  , dateTimeInput :: DateTimeLocalInput.Slot String
  )

_haskellEditorSlot :: Proxy "haskellEditorSlot"
_haskellEditorSlot = Proxy

_jsEditorSlot :: Proxy "jsEditorSlot"
_jsEditorSlot = Proxy

_blocklySlot :: Proxy "blocklySlot"
_blocklySlot = Proxy

_simulationSlot :: Proxy "simulationSlot"
_simulationSlot = Proxy

_simulatorEditorSlot :: Proxy "simulatorEditorSlot"
_simulatorEditorSlot = Proxy

_marloweEditorPageSlot :: Proxy "marloweEditorPageSlot"
_marloweEditorPageSlot = Proxy

_walletSlot :: Proxy "walletSlot"
_walletSlot = Proxy

_currencyInputSlot :: Proxy "currencyInput"
_currencyInputSlot = Proxy

_dateTimeInputSlot :: Proxy "dateTimeInput"
_dateTimeInputSlot = Proxy

-----------------------------------------------------------
type Input = { tzOffset :: Minutes, webpackBuildMode :: WebpackBuildMode }

-- We store `Input` data so we are able to reset the state on logout
type State =
  { input :: Input
  , view :: View
  , jsCompilationResult :: CompilationState
  , jsEditorKeybindings :: KeyBindings
  , activeJSDemo :: String
  , showBottomPanel :: Boolean
  -- TODO: rename to haskellEditorState
  , haskellState :: HE.State
  -- TODO: rename to javascriptEditorState
  , javascriptState :: JS.State
  , marloweEditorState :: ME.State
  , blocklyEditorState :: BE.State
  , simulationState :: Simulation.StateBase ()
  , contractMetadata :: MetaData
  , projects :: Projects.State
  , newProject :: NewProject.State
  , rename :: Rename.State
  , saveAs :: SaveAs.State
  , authStatus :: WebData AuthStatus
  , gistId :: Maybe GistId
  , createGistResult :: WebData Gist
  , loadGistResult :: Either String (WebData Gist)
  , projectName :: String
  , showModal :: Maybe ModalView
  , hasUnsavedChanges :: Boolean
  -- The initial language selected when you create/load a project indicates the workflow a user might take
  -- A user can start with a haskell/javascript example that eventually gets compiled into
  -- marlowe/blockly and run in the simulator, or can create a marlowe/blockly contract directly,
  -- which can be used interchangeably. This is used all across the site to know what are the posible
  -- transitions.
  , workflow :: Maybe Lang
  , featureFlags ::
      { fsProjectStorage :: Boolean
      , logout :: Boolean
      }
  }

_input :: Lens' State Input
_input = prop (Proxy :: _ "input")

_view :: Lens' State View
_view = prop (Proxy :: _ "view")

_jsCompilationResult :: Lens' State CompilationState
_jsCompilationResult = prop (Proxy :: _ "jsCompilationResult")

_jsEditorKeybindings :: Lens' State KeyBindings
_jsEditorKeybindings = prop (Proxy :: _ "jsEditorKeybindings")

_activeJSDemo :: Lens' State String
_activeJSDemo = prop (Proxy :: _ "activeJSDemo")

_showBottomPanel :: Lens' State Boolean
_showBottomPanel = prop (Proxy :: _ "showBottomPanel")

_marloweEditorState :: Lens' State ME.State
_marloweEditorState = prop (Proxy :: _ "marloweEditorState")

_blocklyEditorState :: Lens' State BE.State
_blocklyEditorState = prop (Proxy :: _ "blocklyEditorState")

_haskellState :: Lens' State HE.State
_haskellState = prop (Proxy :: _ "haskellState")

_javascriptState :: Lens' State JS.State
_javascriptState = prop (Proxy :: _ "javascriptState")

_simulationState :: Lens' State Simulation.State
_simulationState = do
  let
    _simulationStateBase = prop (Proxy :: Proxy "simulationState")
    _projectNameProxy = Proxy :: Proxy "projectName"
    get_ s = do
      let
        r = view _simulationStateBase s
        n = view _projectName s
      Record.insert _projectNameProxy n r
    set_ s r =
      set _simulationStateBase (Record.delete _projectNameProxy r)
        <<< set _projectName (Record.get _projectNameProxy r)
        $ s
  lens get_ set_

_contractMetadata :: forall a r. Lens' { contractMetadata :: a | r } a
_contractMetadata = prop (Proxy :: Proxy "contractMetadata")

_projects :: Lens' State Projects.State
_projects = prop (Proxy :: _ "projects")

_newProject :: Lens' State NewProject.State
_newProject = prop (Proxy :: _ "newProject")

_rename :: Lens' State Rename.State
_rename = prop (Proxy :: _ "rename")

_saveAs :: Lens' State SaveAs.State
_saveAs = prop (Proxy :: _ "saveAs")

_authStatus :: Lens' State (WebData AuthStatus)
_authStatus = prop (Proxy :: _ "authStatus")

_gistId :: Lens' State (Maybe GistId)
_gistId = prop (Proxy :: _ "gistId")

_createGistResult :: Lens' State (WebData Gist)
_createGistResult = prop (Proxy :: _ "createGistResult")

_loadGistResult :: Lens' State (Either String (WebData Gist))
_loadGistResult = prop (Proxy :: _ "loadGistResult")

_projectName :: forall r. Lens' { projectName :: String | r } String
_projectName = prop (Proxy :: _ "projectName")

_showModal :: Lens' State (Maybe ModalView)
_showModal = prop (Proxy :: _ "showModal")

_hasUnsavedChanges :: Lens' State Boolean
_hasUnsavedChanges = prop (Proxy :: _ "hasUnsavedChanges")

_workflow :: Lens' State (Maybe Lang)
_workflow = prop (Proxy :: _ "workflow")

currentLang :: State -> Maybe Lang
currentLang state = case state ^. _view of
  HaskellEditor -> Just Haskell
  JSEditor -> Just Javascript
  Simulation -> Just Marlowe
  BlocklyEditor -> Just Blockly
  _ -> Nothing

-- This function checks wether some action that we triggered requires the global state to be present.
-- Initially the code to track this was thought to handle a global boolean state that can be set from the
-- different handleActions, but I wasn't able to set it to false once the Projects modal has completed
-- loading the gists. The reason I wasn't able to do that is that we can't fire a MainFrame.handleAction
-- from a submodule action.
-- The good thing is that this becomes a derived state and we got a global loading for "Save" automatically.
-- The downside is that the logic is a little bit contrived. We may need to rethink when and why we use "_createGistResult"
hasGlobalLoading :: State -> Boolean
hasGlobalLoading state = Projects.modalIsLoading (state ^. _projects) ||
  (projectIsLoadingOrSaving && not isSaveAsModal)
  where
  projectIsLoadingOrSaving = has (_createGistResult <<< _Loading) state

  -- If Action -> ModalView had an Eq instance, we could replace isSaveAsModal with
  -- has (_showModal <<< _Just <<< only SaveProjectAs) state
  isSaveAsModal = case state ^. _showModal of
    Just SaveProjectAs -> true
    _ -> false

-- editable
_timestamp
  :: forall s a
   . Lens' { timestamp :: a | s } a
_timestamp = prop (Proxy :: _ "timestamp")

_value :: forall s a. Lens' { value :: a | s } a
_value = prop (Proxy :: _ "value")

isActiveTab :: State -> View -> Array ClassName
isActiveTab state activeView = state ^. _view <<< (activeClass (eq activeView))

-----------------------------------------------------------
newtype Session = Session
  { projectName :: String
  , gistId :: Maybe GistId
  , workflow :: Maybe Lang
  , contractMetadata :: MetaData
  }

derive instance newtypeSession :: Newtype Session _

derive instance eqSession :: Eq Session

derive instance genericSession :: Generic Session _

instance encodeJsonSession :: EncodeJson Session where
  encodeJson (Session { projectName, gistId, workflow, contractMetadata }) =
    encodeJson
      { projectName
      , gistId: maybe jsonNull encodeJson gistId
      , workflow: maybe jsonNull encodeJson workflow
      , contractMetadata
      }

instance decodeJsonSession :: DecodeJson Session where
  decodeJson json = do
    obj <- decodeJObject json
    projectName <- obj .: "projectName"
    gistId <- obj .:? "gistId"
    workflow <- obj .:? "workflow"
    contractMetadata <- obj .: "contractMetadata"
    pure $ Session { projectName, gistId, workflow, contractMetadata }

stateToSession :: State -> Session
stateToSession
  { projectName
  , gistId
  , workflow
  , contractMetadata
  } =
  Session
    { projectName
    , gistId
    , workflow
    , contractMetadata
    }

sessionToState :: Session -> State -> State
sessionToState (Session sessionData) defaultState =
  defaultState
    { projectName = sessionData.projectName
    , gistId = sessionData.gistId
    , workflow = sessionData.workflow
    , contractMetadata = sessionData.contractMetadata
    }

isAuthenticated :: State -> Boolean
isAuthenticated = has
  (_authStatus <<< _Success <<< authStatusAuthRole <<< _GithubUser)
