module MainFrame.State (component) where

import Prologue hiding (div)

import Auth (AuthRole(..), _GithubUser, authStatusAuthRole)
import Component.Blockly.Types as Blockly
import Component.BottomPanel.Types (Action(..)) as BP
import Component.ConfirmUnsavedNavigation.Types (Action(..)) as ConfirmUnsavedNavigation
import Component.Demos.Types (Action(..), Demo(..)) as Demos
import Component.MetadataTab.State (carryMetadataAction)
import Component.NewProject.Types (Action(..), emptyState) as NewProject
import Component.Projects.State (handleAction) as Projects
import Component.Projects.Types (Action(..), State, _projects, emptyState) as Projects
import Component.Projects.Types (Lang(..))
import Control.Monad.Except (ExceptT(..), lift, runExceptT)
import Control.Monad.Maybe.Extra (hoistMaybe)
import Control.Monad.Maybe.Trans (MaybeT(..), runMaybeT)
import Control.Monad.State (modify_)
import Data.Argonaut.Extra (encodeStringifyJson, parseDecodeJson)
import Data.Bifunctor (lmap)
import Data.Either (either, hush, note)
import Data.Foldable (fold, for_)
import Data.Lens (_Right, assign, has, preview, set, use, view, (^.))
import Data.Lens.Extra (peruse)
import Data.Lens.Index (ix)
import Data.Map as Map
import Data.Maybe (fromMaybe, maybe)
import Data.Newtype (un, unwrap)
import Data.RawJson (RawJson(..))
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect)
import Effect.Class.Console (log)
import Gist (Gist, gistDescription, gistId)
import Gists.Extra (_GistId)
import Gists.Types (GistAction(..))
import Gists.Types (parseGistUrl) as Gists
import Halogen (Component, liftEffect, subscribe')
import Halogen as H
import Halogen.Analytics (withAnalytics)
import Halogen.Extra (mapSubmodule)
import Halogen.Monaco (KeyBindings(DefaultBindings))
import Halogen.Monaco as Monaco
import Halogen.Query (HalogenM)
import Halogen.Query.Event (eventListener)
import Language.Marlowe.Extended.V1.Metadata
  ( emptyContractMetadata
  , getHintsFromMetadata
  )
import LoginPopup (informParentAndClose, openLoginPopup)
import MainFrame.Types
  ( Action(..)
  , ChildSlots
  , Input
  , ModalView(..)
  , Query(..)
  , Session(..)
  , State
  , View(..)
  , _authStatus
  , _blocklyEditorState
  , _contractMetadata
  , _createGistResult
  , _gistId
  , _hasUnsavedChanges
  , _haskellState
  , _input
  , _javascriptState
  , _loadGistResult
  , _marloweEditorState
  , _projectName
  , _projects
  , _rename
  , _saveAs
  , _showBottomPanel
  , _showModal
  , _simulationState
  , _view
  , _workflow
  , sessionToState
  , stateToSession
  )
import MainFrame.View (render)
import Marlowe (Api, getApiGistsByGistId)
import Marlowe as Server
import Marlowe.Gists (PlaygroundFiles, mkNewGist, mkPatchGist, playgroundFiles)
import Network.RemoteData (RemoteData(..), _Success, fromEither)
import Page.BlocklyEditor.State as BlocklyEditor
import Page.BlocklyEditor.Types (_marloweCode)
import Page.BlocklyEditor.Types as BE
import Page.HaskellEditor.State as HaskellEditor
import Page.HaskellEditor.Types
  ( Action(..)
  , State
  , _ContractString
  , _metadataHintInfo
  , initialState
  ) as HE
import Page.JavascriptEditor.State as JavascriptEditor
import Page.JavascriptEditor.Types
  ( Action(..)
  , State
  , _ContractString
  , _metadataHintInfo
  , initialState
  ) as JS
import Page.JavascriptEditor.Types (CompilationState(..))
import Page.MarloweEditor.State as MarloweEditor
import Page.MarloweEditor.Types as ME
import Page.Simulation.State as Simulation
import Page.Simulation.Types as ST
import Rename.State (handleAction) as Rename
import Rename.Types (Action(..), State, emptyState) as Rename
import Router (Route, SubRoute)
import Router as Router
import Routing.Duplex as RD
import Routing.Hash as Routing
import SaveAs.State (handleAction) as SaveAs
import SaveAs.Types (Action(..), State, _status, emptyState) as SaveAs
import Servant.PureScript (class MonadAjax, printAjaxError)
import SessionStorage as SessionStorage
import Simple.JSON (unsafeStringify)
import StaticData (gistIdLocalStorageKey)
import StaticData as StaticData
import Types (WebpackBuildMode(..))
import Web.HTML (window) as Web
import Web.HTML.HTMLDocument (toEventTarget)
import Web.HTML.Window (document) as Web
import Web.HTML.Window as Window
import Web.UIEvent.KeyboardEvent as KE
import Web.UIEvent.KeyboardEvent.EventTypes (keyup)

initialState
  :: Input -> State
initialState input@{ tzOffset, webpackBuildMode } =
  { input
  , view: HomePage
  , jsCompilationResult: NotCompiled
  , showBottomPanel: true
  , haskellState: HE.initialState tzOffset
  , javascriptState: JS.initialState tzOffset
  , marloweEditorState: ME.initialState tzOffset
  , blocklyEditorState: BE.initialState tzOffset
  , simulationState: Simulation.mkStateBase tzOffset
  , jsEditorKeybindings: DefaultBindings
  , activeJSDemo: mempty
  , contractMetadata: emptyContractMetadata
  , projects: Projects.emptyState
  , newProject: NewProject.emptyState
  , rename: Rename.emptyState
  , saveAs: SaveAs.emptyState
  , authStatus: NotAsked
  , gistId: Nothing
  , createGistResult: NotAsked
  , loadGistResult: Right NotAsked
  , projectName: "Untitled Project"
  , showModal: Nothing
  , hasUnsavedChanges: false
  , workflow: Nothing
  , featureFlags:
      { fsProjectStorage: webpackBuildMode == Development
      , logout: webpackBuildMode == Development
      }
  }

------------------------------------------------------------
component
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => Component Query Input Void m
component =
  H.mkComponent
    { initialState
    , render
    , eval:
        H.mkEval
          { handleQuery
          , handleAction: fullHandleAction
          , receive: const Nothing
          , initialize: Just Init
          , finalize: Nothing
          }
    }

toSimulation
  :: forall m a
   . Functor m
  => HalogenM ST.State ST.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toSimulation = mapSubmodule _simulationState SimulationAction

toHaskellEditor
  :: forall m a
   . Functor m
  => HalogenM HE.State HE.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toHaskellEditor = mapSubmodule _haskellState HaskellAction

toMarloweEditor
  :: forall m a
   . Functor m
  => HalogenM ME.State ME.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toMarloweEditor = mapSubmodule _marloweEditorState MarloweEditorAction

toJavascriptEditor
  :: forall m a
   . Functor m
  => HalogenM JS.State JS.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toJavascriptEditor = mapSubmodule _javascriptState JavascriptAction

toBlocklyEditor
  :: forall m a
   . Functor m
  => HalogenM BE.State BE.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toBlocklyEditor = mapSubmodule _blocklyEditorState BlocklyEditorAction

toProjects
  :: forall m a
   . Functor m
  => HalogenM Projects.State Projects.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toProjects = mapSubmodule _projects ProjectsAction

toRename
  :: forall m a
   . Functor m
  => HalogenM Rename.State Rename.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toRename = mapSubmodule _rename RenameAction

toSaveAs
  :: forall m a
   . Functor m
  => HalogenM SaveAs.State SaveAs.Action ChildSlots Void m a
  -> HalogenM State Action ChildSlots Void m a
toSaveAs = mapSubmodule _saveAs SaveAsAction

------------------------------------------------------------
handleSubRoute
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => SubRoute
  -> HalogenM State Action ChildSlots Void m Unit
handleSubRoute Router.Home = selectView HomePage

handleSubRoute Router.Simulation = selectView Simulation

handleSubRoute Router.MarloweEditor = selectView MarloweEditor

handleSubRoute Router.HaskellEditor = selectView HaskellEditor

handleSubRoute Router.JSEditor = selectView JSEditor

handleSubRoute Router.Blockly = selectView BlocklyEditor

-- This route is supposed to be called by the github oauth flow after a succesful login flow
-- It is supposed to be run inside a popup window
handleSubRoute Router.GithubAuthCallback = do
  authResult <- lift $ Server.getApiOauthStatus
  case authResult of
    (Right authStatus) -> liftEffect $ informParentAndClose $ view
      authStatusAuthRole
      authStatus
    -- TODO: is it worth showing a particular view for Failure, NotAsked and Loading?
    -- Modifying this will mean to also modify the render function in the mainframe to be able to draw without
    -- the headers/footers as this is supposed to be a dialog/popup
    _ -> pure unit

handleRoute
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => Route
  -> HalogenM State Action ChildSlots Void m Unit
handleRoute { gistId: (Just gistId), subroute } = do
  handleActionWithoutNavigationGuard (GistAction (SetGistUrl (unwrap gistId)))
  handleActionWithoutNavigationGuard (GistAction LoadGist)
  handleSubRoute subroute

handleRoute { subroute } = handleSubRoute subroute

handleQuery
  :: forall m a
   . MonadAff m
  => MonadAjax Api m
  => Query a
  -> HalogenM State Action ChildSlots Void m (Maybe a)
handleQuery (ChangeRoute route next) = do
  -- Without the following each route is handled twice, once when we call selectView ourselves
  -- and another which is triggered in Main, when the route changes.
  currentView <- use _view
  when (routeToView route /= Just currentView) $ handleRoute route
  pure $ Just next

------------------------------------------------------------
fullHandleAction
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => Action
  -> HalogenM State Action ChildSlots Void m Unit
fullHandleAction =
  withAccidentalNavigationGuard
    $ withSessionStorage
    $ withAnalytics
        handleAction

handleActionWithoutNavigationGuard
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => Action
  -> HalogenM State Action ChildSlots Void m Unit
handleActionWithoutNavigationGuard =
  withSessionStorage
    $ withAnalytics
        ( handleAction
        )

-- This handleAction can be called recursively, but because we use HOF to extend the functionality
-- of the component, whenever we need to recurse we most likely be calling one of the extended functions
-- defined above (handleActionWithoutNavigationGuard or fullHandleAction)
handleAction
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => Action
  -> HalogenM State Action ChildSlots Void m Unit
handleAction Init = do
  hash <- liftEffect Routing.getHash
  case (RD.parse Router.route) hash of
    Right route -> handleRoute route
    Left _ -> handleRoute { subroute: Router.Home, gistId: Nothing }
  document <- liftEffect $ Web.document =<< Web.window
  subscribe' \sid ->
    eventListener keyup (toEventTarget document)
      (map (HandleKey sid) <<< KE.fromEvent)
  checkAuthStatus
  -- Load session data if available
  void
    $ runMaybeT do
        sessionJSON <- MaybeT $ liftEffect $ SessionStorage.getItem
          StaticData.sessionStorageKey
        session <- hoistMaybe $ hush $ parseDecodeJson sessionJSON
        let
          contractMetadata = un Session session # _.contractMetadata
          metadataHints = getHintsFromMetadata contractMetadata
        H.modify_ $ sessionToState session
          <<< set (_haskellState <<< HE._metadataHintInfo) metadataHints
          <<< set (_javascriptState <<< JS._metadataHintInfo) metadataHints

handleAction (HandleKey _ ev)
  | KE.key ev == "Escape" = assign _showModal Nothing
  | KE.key ev == "Enter" = do
      modalView <- use _showModal
      case modalView of
        Just RenameProject -> handleAction (RenameAction Rename.SaveProject)
        Just SaveProjectAs -> handleAction (SaveAsAction SaveAs.SaveProject)
        _ -> pure unit
  | otherwise = pure unit

handleAction (HaskellAction action) = do
  metadata <- use _contractMetadata

  toHaskellEditor (HaskellEditor.handleAction metadata action)
  case action of
    HE.SendResultToSimulator -> do
      mContract <- peruse (_haskellState <<< HE._ContractString)
      let
        contract = fold mContract
      sendToSimulation contract
    HE.HandleEditorMessage (Monaco.TextChanged _) ->
      setUnsavedChangesForLanguage Haskell true
    HE.InitHaskellProject _ _ -> setUnsavedChangesForLanguage Haskell false
    HE.BottomPanelAction (BP.PanelAction (HE.MetadataAction metadataAction)) ->
      carryMetadataAction metadataAction
    _ -> pure unit

handleAction (JavascriptAction action) = do
  metadata <- use _contractMetadata

  toJavascriptEditor (JavascriptEditor.handleAction metadata action)
  case action of
    JS.SendResultToSimulator -> do
      mContract <- peruse (_javascriptState <<< JS._ContractString)
      let
        contract = fold mContract
      sendToSimulation contract
    JS.HandleEditorMessage (Monaco.TextChanged _) ->
      setUnsavedChangesForLanguage Javascript true
    JS.InitJavascriptProject _ _ -> setUnsavedChangesForLanguage Javascript
      false
    JS.BottomPanelAction (BP.PanelAction (JS.MetadataAction metadataAction)) ->
      carryMetadataAction metadataAction
    _ -> pure unit

handleAction (MarloweEditorAction action) = do
  metadata <- use _contractMetadata
  toMarloweEditor (MarloweEditor.handleAction metadata action)

  case action of
    ME.SendToSimulator -> do
      mContents <- MarloweEditor.editorGetValue
      for_ mContents \contents ->
        sendToSimulation contents
    ME.ViewAsBlockly -> do
      mSource <- MarloweEditor.editorGetValue
      for_ mSource \source -> do
        void $ toBlocklyEditor $ BlocklyEditor.handleAction metadata $
          BE.InitBlocklyProject source
        assign _workflow (Just Blockly)
        selectView BlocklyEditor
    ME.HandleEditorMessage (Monaco.TextChanged _) ->
      setUnsavedChangesForLanguage Marlowe true
    ME.InitMarloweProject _ -> setUnsavedChangesForLanguage Marlowe false
    ME.BottomPanelAction (BP.PanelAction (ME.MetadataAction metadataAction)) ->
      carryMetadataAction metadataAction
    _ -> pure unit

handleAction (BlocklyEditorAction action) = do
  metadata <- use _contractMetadata

  toBlocklyEditor $ BlocklyEditor.handleAction metadata action
  case action of
    BE.SendToSimulator -> do
      mCode <- use (_blocklyEditorState <<< _marloweCode)
      for_ mCode \contents -> sendToSimulation contents
    BE.ViewAsMarlowe -> do
      -- TODO: doing an effect that returns a maybe value and doing an action on the possible
      -- result is a pattern that we have repeated a lot in this file. See if we could refactor
      -- into something like this: https://github.com/input-output-hk/plutus/pull/2560#discussion_r549892291
      mCode <- use (_blocklyEditorState <<< _marloweCode)
      for_ mCode \code -> do
        selectView MarloweEditor
        assign _workflow (Just Marlowe)
        toMarloweEditor $ MarloweEditor.handleAction metadata $
          ME.InitMarloweProject
            code
    BE.HandleBlocklyMessage Blockly.CodeChange -> setUnsavedChangesForLanguage
      Blockly
      true
    BE.BottomPanelAction (BP.PanelAction (BE.MetadataAction metadataAction)) ->
      carryMetadataAction metadataAction
    _ -> pure unit

handleAction (SimulationAction action) = do
  metadata <- use _contractMetadata
  toSimulation (Simulation.handleAction metadata action)
  case action of
    ST.EditSource -> do
      mLang <- use _workflow
      for_ mLang \lang -> selectView $ selectLanguageView lang
    _ -> pure unit

handleAction (ChangeView view) = selectView view

handleAction (ShowBottomPanel val) = do
  assign _showBottomPanel val
  pure unit

-- TODO: modify gist action type to take a gistid as a parameter
-- https://github.com/input-output-hk/plutus/pull/2498#discussion_r533478042
handleAction (ProjectsAction action@(Projects.LoadProject lang gistId)) = do
  assign _createGistResult Loading
  res <-
    runExceptT
      $ do
          gist <- ExceptT $ lift $ getApiGistsByGistId gistId
          lift $ loadGist gist
          pure gist
  case res of
    Right gist ->
      modify_
        ( set _createGistResult (Success gist)
            <<< set _showModal Nothing
            <<< set _workflow (Just lang)
        )
    Left error ->
      modify_
        ( set _createGistResult (Failure error)
            <<< set (_projects <<< Projects._projects)
              (Failure "Failed to load gist")
            <<< set _workflow Nothing
        )
  toProjects $ Projects.handleAction action
  selectView $ selectLanguageView lang

handleAction (ProjectsAction Projects.Cancel) = fullHandleAction CloseModal

handleAction (ProjectsAction action) = toProjects $ Projects.handleAction action

handleAction (NewProjectAction (NewProject.CreateProject lang)) = do
  assign _projectName "New Project"
  assign _gistId Nothing
  assign _createGistResult NotAsked
  assign _contractMetadata emptyContractMetadata

  -- TODO: Remove gistIdLocalStorageKey and use global session management (MainFrame.stateToSession)
  liftEffect $ SessionStorage.setItem gistIdLocalStorageKey mempty
  case lang of
    Haskell ->
      for_ (Map.lookup "Example" StaticData.demoFiles) \contents -> do
        toHaskellEditor $ HaskellEditor.handleAction emptyContractMetadata $
          HE.InitHaskellProject
            mempty
            contents
    Javascript ->
      for_ (Map.lookup "Example" StaticData.demoFilesJS) \contents -> do
        toJavascriptEditor $ JavascriptEditor.handleAction emptyContractMetadata
          $
            JS.InitJavascriptProject mempty contents
    Marlowe ->
      for_ (Map.lookup "Example" StaticData.marloweContracts) \contents -> do
        toMarloweEditor $ MarloweEditor.handleAction emptyContractMetadata $
          ME.InitMarloweProject
            contents
    Blockly ->
      for_ (Map.lookup "Example" StaticData.marloweContracts) \contents -> do
        toBlocklyEditor $ BlocklyEditor.handleAction emptyContractMetadata $
          BE.InitBlocklyProject
            contents
  selectView $ selectLanguageView lang
  modify_
    ( set _showModal Nothing
        <<< set _workflow (Just lang)
        <<< set _hasUnsavedChanges false
    )

handleAction (NewProjectAction NewProject.Cancel) = fullHandleAction CloseModal

handleAction (DemosAction (Demos.LoadDemo lang (Demos.Demo key))) = do
  assign _projectName metadata.contractName
  assign _showModal Nothing
  assign _workflow (Just lang)
  assign _hasUnsavedChanges false
  assign _gistId Nothing
  assign _contractMetadata metadata
  selectView $ selectLanguageView lang
  case lang of
    Haskell ->
      for_ (Map.lookup key StaticData.demoFiles) \contents ->
        toHaskellEditor $ HaskellEditor.handleAction metadata $
          HE.InitHaskellProject
            metadataHints
            contents
    Javascript ->
      for_ (Map.lookup key StaticData.demoFilesJS) \contents -> do
        toJavascriptEditor $ JavascriptEditor.handleAction metadata $
          JS.InitJavascriptProject metadataHints contents
    Marlowe -> do
      for_ (preview (ix key) StaticData.marloweContracts) \contents -> do
        toMarloweEditor $ MarloweEditor.handleAction metadata $
          ME.InitMarloweProject
            contents
    Blockly -> do
      for_ (preview (ix key) StaticData.marloweContracts) \contents -> do
        toBlocklyEditor $ BlocklyEditor.handleAction metadata $
          BE.InitBlocklyProject
            contents
  where
  metadata = fromMaybe emptyContractMetadata $ Map.lookup key
    StaticData.demoFilesMetadata

  metadataHints = getHintsFromMetadata metadata

handleAction (DemosAction Demos.Cancel) = fullHandleAction CloseModal

handleAction (RenameAction action@Rename.SaveProject) = do
  projectName <- use (_rename <<< _projectName)
  assign _projectName projectName
  assign _showModal Nothing
  toRename $ Rename.handleAction action

handleAction (RenameAction action) = toRename $ Rename.handleAction action

handleAction (SaveAsAction action@SaveAs.SaveProject) = do
  currentName <- use _projectName
  currentGistId <- use _gistId
  projectName <- use (_saveAs <<< _projectName)

  assign _projectName projectName
  assign _gistId Nothing
  assign (_saveAs <<< SaveAs._status) Loading

  handleGistAction PublishOrUpdateGist
  res <- peruse (_createGistResult <<< _Success)
  case res of
    Just gist -> do
      liftEffect $ SessionStorage.setItem gistIdLocalStorageKey
        (gist ^. (gistId <<< _GistId))
      modify_
        ( set _showModal Nothing
            <<< set (_saveAs <<< SaveAs._status) NotAsked
        )
    Nothing -> do
      assign (_saveAs <<< SaveAs._status) (Failure "Could not save project")
      assign _gistId currentGistId
      assign _projectName currentName
  toSaveAs $ SaveAs.handleAction action

handleAction (SaveAsAction SaveAs.Cancel) = fullHandleAction CloseModal

handleAction (SaveAsAction action) = toSaveAs $ SaveAs.handleAction action

handleAction CheckAuthStatus = checkAuthStatus

handleAction (GistAction subEvent) = handleGistAction subEvent

handleAction (OpenModal OpenProject) = do
  assign _showModal $ Just OpenProject
  toProjects $ Projects.handleAction Projects.LoadProjects

handleAction (OpenModal RenameProject) = do
  currentName <- use _projectName
  assign (_rename <<< _projectName) currentName
  assign _showModal $ Just RenameProject

handleAction (OpenModal modalView) = assign _showModal $ Just modalView

handleAction CloseModal = assign _showModal Nothing

handleAction (OpenLoginPopup intendedAction) = do
  authRole <- liftAff openLoginPopup
  fullHandleAction CloseModal
  assign (_authStatus <<< _Success <<< authStatusAuthRole) authRole
  case authRole of
    Anonymous -> pure unit
    GithubUser -> fullHandleAction intendedAction

handleAction (ConfirmUnsavedNavigationAction intendedAction modalAction) =
  handleConfirmUnsavedNavigationAction intendedAction modalAction

handleAction Logout = do
  lift Server.getApiLogout >>= case _ of
    -- TODO: Proper error reporting
    Left err -> do
      log "Logout request failed:"
      log $ unsafeStringify err
      pure unit
    Right (RawJson _) -> do
      (input :: Input) <- use _input
      selectView HomePage
      H.put $ (initialState input :: State)
      handleAction Init

sendToSimulation
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => String
  -> HalogenM State Action ChildSlots Void m Unit
sendToSimulation contract = do
  metadata <- use _contractMetadata
  selectView Simulation
  toSimulation $ Simulation.handleAction metadata (ST.LoadContract contract)

selectLanguageView :: Lang -> View
selectLanguageView = case _ of
  Haskell -> HaskellEditor
  Marlowe -> MarloweEditor
  Blockly -> BlocklyEditor
  Javascript -> JSEditor

routeToView :: Route -> Maybe View
routeToView { subroute } = case subroute of
  Router.Home -> Just HomePage
  Router.Simulation -> Just Simulation
  Router.HaskellEditor -> Just HaskellEditor
  Router.MarloweEditor -> Just MarloweEditor
  Router.JSEditor -> Just JSEditor
  Router.Blockly -> Just BlocklyEditor
  Router.GithubAuthCallback -> Nothing

viewToRoute :: View -> Router.SubRoute
viewToRoute = case _ of
  HomePage -> Router.Home
  MarloweEditor -> Router.MarloweEditor
  Simulation -> Router.Simulation
  HaskellEditor -> Router.HaskellEditor
  JSEditor -> Router.JSEditor
  BlocklyEditor -> Router.Blockly

------------------------------------------------------------
checkAuthStatus
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => HalogenM State Action ChildSlots Void m Unit
checkAuthStatus = do
  assign _authStatus Loading
  authResult <- lift Server.getApiOauthStatus
  assign _authStatus $ fromEither authResult

------------------------------------------------------------
createFiles
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => HalogenM State Action ChildSlots Void m PlaygroundFiles
createFiles = do
  let
    pruneEmpty :: forall a. Eq a => Monoid a => Maybe a -> Maybe a
    pruneEmpty (Just v)
      | v == mempty = Nothing

    pruneEmpty m = m

    -- playground is a meta-data file that we currently just use as a tag to check if a gist is a marlowe playground gist
    playground = "{}"
  metadata <- Just <$> encodeStringifyJson <$> use _contractMetadata
  workflow <- use _workflow
  let
    emptyFiles = (mempty :: PlaygroundFiles)
      { playground = playground, metadata = metadata }
  case workflow of
    Just Marlowe -> do
      marlowe <- pruneEmpty <$> MarloweEditor.editorGetValue
      pure $ emptyFiles { marlowe = marlowe }
    Just Blockly -> do
      blockly <- pruneEmpty <$> BlocklyEditor.editorGetValue
      pure $ emptyFiles { blockly = blockly }
    Just Haskell -> do
      haskell <- pruneEmpty <$> HaskellEditor.editorGetValue
      pure $ emptyFiles { haskell = haskell }
    Just Javascript -> do
      javascript <- pruneEmpty <$> toJavascriptEditor
        JavascriptEditor.editorGetValue
      pure $ emptyFiles { javascript = javascript }
    Nothing -> mempty

handleGistAction
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => GistAction
  -> HalogenM State Action ChildSlots Void m Unit
handleGistAction PublishOrUpdateGist = do
  description <- use _projectName
  files <- createFiles
  void
    $ runMaybeT do
        mGist <- use _gistId
        assign _createGistResult Loading
        newResult <-
          lift
            $ lift
            $ case mGist of
                Nothing -> Server.postApiGists $ mkNewGist description files
                Just gistId -> Server.patchApiGistsByGistId
                  (mkPatchGist description files)
                  gistId
        assign _createGistResult $ fromEither newResult
        gistId <- hoistMaybe $ preview (_Right <<< gistId) newResult
        modify_
          ( set _gistId (Just gistId)
              <<< set _loadGistResult (Right NotAsked)
              <<< set _hasUnsavedChanges false
          )

handleGistAction (SetGistUrl url) = do
  case Gists.parseGistUrl url of
    Right newGistUrl ->
      modify_
        ( set _createGistResult NotAsked
            <<< set _loadGistResult (Right NotAsked)
            <<< set _gistId (Just newGistUrl)
        )
    Left _ -> pure unit

-- TODO: This action is only called when loading the site with a gistid param, something like
-- https://<base_url>/#/marlowe?gistid=<gist_id>
-- But it's not loading the gist correctly. For now I'm leaving it as it is, but we should rethink
-- this functionality in the redesign.
--
-- A separate issue is that the gistid is loaded in the state instead of passing it as a parameter
-- to the LoadGist action
-- https://github.com/input-output-hk/plutus/pull/2498#discussion_r533478042
handleGistAction LoadGist = do
  res <-
    runExceptT
      $ do
          eGistId <- ExceptT $ note "Gist Id not set." <$> use _gistId
          assign _loadGistResult $ Right Loading
          aGist <- lift $ lift $ Server.getApiGistsByGistId eGistId
          assign _loadGistResult $ Right $ fromEither aGist
          gist <-
            ExceptT
              $ pure
              $ toEither (Left "Gist not loaded.")
              $ lmap printAjaxError
              $ fromEither aGist
          lift $ loadGist gist
          pure aGist
  assign _loadGistResult $ map fromEither res
  where
  toEither :: forall e a. Either e a -> RemoteData e a -> Either e a
  toEither _ (Success a) = Right a

  toEither _ (Failure e) = Left e

  toEither x Loading = x

  toEither x NotAsked = x

-- other gist actions are irrelevant here
handleGistAction _ = pure unit

loadGist
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => Gist
  -> HalogenM State Action ChildSlots Void m Unit
loadGist gist = do
  let
    { marlowe
    , blockly
    , haskell
    , javascript
    , metadata: mMetadataJSON
    } = playgroundFiles gist

    description = view gistDescription gist

    gistId' = preview gistId gist

    metadata = maybe emptyContractMetadata
      (either (const emptyContractMetadata) identity <<< parseDecodeJson)
      mMetadataJSON

    metadataHints = getHintsFromMetadata metadata
  -- Restore or reset all editors
  toHaskellEditor
    $ HaskellEditor.handleAction
        metadata
    $ HE.InitHaskellProject metadataHints
    $ fromMaybe mempty haskell
  toJavascriptEditor
    $ JavascriptEditor.handleAction
        metadata
    $ JS.InitJavascriptProject metadataHints
    $ fromMaybe mempty javascript
  toMarloweEditor $ MarloweEditor.handleAction metadata $ ME.InitMarloweProject
    $
      fromMaybe mempty marlowe
  toBlocklyEditor $ BlocklyEditor.handleAction metadata $ BE.InitBlocklyProject
    $
      fromMaybe mempty blockly
  assign _contractMetadata metadata
  assign _gistId gistId'
  assign _projectName description

------------------------------------------------------------
-- Handles the actions fired by the Confirm Unsaved Navigation modal
handleConfirmUnsavedNavigationAction
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => Action
  -> ConfirmUnsavedNavigation.Action
  -> HalogenM State Action ChildSlots Void m Unit
handleConfirmUnsavedNavigationAction intendedAction modalAction = do
  fullHandleAction CloseModal
  case modalAction of
    ConfirmUnsavedNavigation.Cancel -> pure unit
    ConfirmUnsavedNavigation.DontSaveProject ->
      handleActionWithoutNavigationGuard intendedAction
    ConfirmUnsavedNavigation.SaveProject -> do
      state <- H.get
      -- TODO: This was taken from the view, from the gistModal helper. I think we should
      -- refactor into a `Save (Maybe Action)` action. The handler for that should do
      -- this check and call the next action as a continuation
      if
        has (_authStatus <<< _Success <<< authStatusAuthRole <<< _GithubUser)
          state then do
        fullHandleAction $ GistAction PublishOrUpdateGist
        fullHandleAction intendedAction
      else
        fullHandleAction $ OpenModal $ GithubLogin $
          ConfirmUnsavedNavigationAction intendedAction modalAction

setUnsavedChangesForLanguage
  :: forall m. Lang -> Boolean -> HalogenM State Action ChildSlots Void m Unit
setUnsavedChangesForLanguage lang value = do
  workflow <- use _workflow
  when (workflow == Just lang)
    $ assign _hasUnsavedChanges value

-- This is a HOF intented to be used on top of handleAction. It prevents the user from accidentally doing an Action that
-- would result in losing the progress.
withAccidentalNavigationGuard
  :: forall m
   . MonadAff m
  => MonadAjax Api m
  => (Action -> HalogenM State Action ChildSlots Void m Unit)
  -> Action
  -> HalogenM State Action ChildSlots Void m Unit
withAccidentalNavigationGuard handleAction' action = do
  currentView <- use _view
  hasUnsavedChanges <- use _hasUnsavedChanges
  if viewIsGuarded currentView && actionIsGuarded && hasUnsavedChanges then
    -- If the action would result in the user losing the work, we present a
    -- modal to confirm, cancel or save the work and we preserve the intended action
    -- to be executed after.
    fullHandleAction $ OpenModal $ ConfirmUnsavedNavigation action
  else
    handleAction' action
  where
  -- Which pages needs to be guarded.
  viewIsGuarded = case _ of
    HomePage -> false
    _ -> true

  -- What actions would result in losing the work.
  actionIsGuarded = case action of
    (ChangeView HomePage) -> true
    (NewProjectAction (NewProject.CreateProject _)) -> true
    (ProjectsAction (Projects.LoadProject _ _)) -> true
    (DemosAction (Demos.LoadDemo _ _)) -> true
    _ -> false

------------------------------------------------------------
selectView
  :: forall m action message
   . MonadEffect m
  => View
  -> HalogenM State action ChildSlots message m Unit
selectView view = do
  liftEffect $ Routing.setHash
    (RD.print Router.route { subroute: viewToRoute view, gistId: Nothing })
  assign _view view
  liftEffect do
    window <- Web.window
    Window.scroll 0 0 window
  case view of
    HomePage -> modify_ (set _workflow Nothing <<< set _hasUnsavedChanges false)
    _ -> pure unit

------------------------------------------------------------
withSessionStorage
  :: forall m
   . MonadAff m
  => (Action -> HalogenM State Action ChildSlots Void m Unit)
  -> Action
  -> HalogenM State Action ChildSlots Void m Unit
withSessionStorage handleAction' action = do
  preSession <- H.gets stateToSession
  handleAction' action
  postSession <- H.gets stateToSession
  when (preSession /= postSession)
    $ liftEffect
    $ SessionStorage.setItem StaticData.sessionStorageKey
    $ encodeStringifyJson postSession
