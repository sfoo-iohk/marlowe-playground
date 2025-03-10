module MainFrame.View where

import Prologue hiding (div)

import Auth (_GithubUser, authStatusAuthRole)
import Component.Modal.View (modal)
import Contrib.Data.Array.Builder ((:>))
import Contrib.Data.Array.Builder as AB
import Data.Lens (has, (^.))
import Data.Maybe (isNothing)
import Data.Monoid (guard)
import Effect.Aff.Class (class MonadAff)
import Gists.Types (GistAction(..))
import Halogen (ComponentHTML)
import Halogen.Classes (marlowePlayLogo)
import Halogen.Css (classNames)
import Halogen.Extra (renderSubmodule)
import Halogen.HTML
  ( HTML
  , a
  , div
  , div_
  , footer
  , h1
  , header
  , img
  , main
  , section
  , span
  , text
  )
import Halogen.HTML.Events (onClick)
import Halogen.HTML.Properties (href, id, src, target)
import Halogen.HTML.Properties.ARIA (label, role)
import Home as Home
import Icons (Icon(..), icon)
import MainFrame.Types
  ( Action(..)
  , ChildSlots
  , ModalView(..)
  , State
  , View(..)
  , _authStatus
  , _blocklyEditorState
  , _contractMetadata
  , _createGistResult
  , _gistId
  , _hasUnsavedChanges
  , _haskellState
  , _javascriptState
  , _marloweEditorState
  , _projectName
  , _simulationState
  , _view
  , hasGlobalLoading
  , isAuthenticated
  )
import Network.RemoteData (_Loading, _Success)
import Page.BlocklyEditor.View as BlocklyEditor
import Page.HaskellEditor.View (otherActions, render) as HaskellEditor
import Page.JavascriptEditor.View as JSEditor
import Page.MarloweEditor.View as MarloweEditor
import Page.Simulation.View as Simulation

render
  :: forall m
   . MonadAff m
  => State
  -> ComponentHTML Action ChildSlots m
render state =
  div [ classNames [ "site-wrap" ] ]
    ( [ header [ classNames [ "no-margins", "flex", "flex-col" ] ]
          [ div
              [ classNames
                  [ "flex"
                  , "items-center"
                  , "justify-between"
                  , "bg-gray-dark"
                  , "px-medium"
                  , "py-small"
                  ]
              ]
              [ img
                  [ classNames [ "h-10", "cursor-pointer" ]
                  , onClick $ const $ ChangeView HomePage
                  , src marlowePlayLogo
                  ]
              , projectTitle
              , div_ $ AB.unsafeBuild $ do
                  let
                    tutorial = a
                      [ href "https://docs.marlowe.iohk.io/tutorials"
                      , target "_blank"
                      , classNames [ "font-semibold" ]
                      ]
                      [ text "Tutorial" ]
                    logout = a
                      [ onClick $ const Logout
                      , classNames [ "font-semibold", "ml-4" ]
                      ]
                      [ text "Logout" ]
                  tutorial
                    :> guard
                      (isAuthenticated state && state.featureFlags.logout)
                      (AB.cons logout)

              -- Link disabled as the Actus labs is not working properly. Future plans might include moving this functionality to Marlowe run
              -- , a [ onClick $ const $ ChangeView ActusBlocklyEditor, classNames [ "ml-medium", "font-semibold" ] ] [ text "Actus Labs" ]
              ]
          , topBar
          ]
      , main []
          [ section [ id "main-panel" ] case state ^. _view of
              HomePage -> [ Home.render state ]
              Simulation ->
                [ renderSubmodule
                    _simulationState
                    SimulationAction
                    (Simulation.render (state ^. _contractMetadata))
                    state
                ]
              MarloweEditor ->
                [ renderSubmodule
                    _marloweEditorState
                    MarloweEditorAction
                    (MarloweEditor.render (state ^. _contractMetadata))
                    state
                ]
              HaskellEditor ->
                [ renderSubmodule
                    _haskellState
                    HaskellAction
                    (HaskellEditor.render (state ^. _contractMetadata))
                    state
                ]
              JSEditor ->
                [ renderSubmodule
                    _javascriptState
                    JavascriptAction
                    (JSEditor.render (state ^. _contractMetadata))
                    state
                ]
              BlocklyEditor ->
                [ renderSubmodule
                    _blocklyEditorState
                    BlocklyEditorAction
                    (BlocklyEditor.render (state ^. _contractMetadata))
                    state
                ]
          ]
      , modal state
      , globalLoadingOverlay
      , footer
          [ classNames
              [ "flex"
              , "justify-between"
              , "px-medium"
              , "py-small"
              , "bg-gray-dark"
              , "font-semibold"
              ]
          ]
          [ div [ classNames [ "flex" ] ]
              [ a
                  [ href "https://cardano.org/"
                  , target "_blank"
                  , classNames [ "pr-small" ]
                  ]
                  [ text "cardano.org" ]
              , a
                  [ href "https://iohk.io/"
                  , target "_blank"
                  , classNames [ "pl-small" ]
                  ]
                  [ text "iohk.io" ]
              ]
          , div_ [ text (copyright <> " 2023 IOHK Ltd") ]
          , div [ classNames [ "flex" ] ]
              [ a
                  [ href
                      "https://discord.com/channels/826816523368005654/936295815926927390"
                  , target "_blank"
                  , classNames [ "pr-small" ]
                  ]
                  [ text "Discord" ]
              , a
                  [ href "https://iohk.zendesk.com/hc/en-us/requests/new"
                  , target "_blank"
                  , classNames [ "pl-small" ]
                  ]
                  [ text "ZenDesk" ]
              ]
          ]
      ]
    )
  where
  copyright = "\x00A9"

  projectTitle = case state ^. _view of
    HomePage -> text ""
    _ ->
      let
        title = state ^. _projectName

        unsavedChangesIndicator =
          if state ^. _hasUnsavedChanges then "*" else ""

        isLoading = has (_createGistResult <<< _Loading) state

        spinner =
          if isLoading then icon Spinner else div [ classNames [ "empty" ] ] []
      in
        div
          [ classNames [ "project-title" ]
          , role "heading"
          , label "project-title"
          ]
          [ h1 [ classNames [ "text-lg" ] ]
              {- TODO: Fix style when name is super long -}
              [ text title
              , span [ classNames [ "unsave-change-indicator" ] ]
                  [ text unsavedChangesIndicator ]
              ]
          , spinner
          ]

  topBar =
    if showtopBar then
      div
        [ classNames [ "global-actions" ] ]
        ([ menuBar state ] <> otherActions (state ^. _view))
    else
      div_ []

  showtopBar = case state ^. _view of
    HaskellEditor -> true
    JSEditor -> true
    BlocklyEditor -> true
    Simulation -> true
    MarloweEditor -> true
    _ -> false

  otherActions HaskellEditor =
    [ renderSubmodule _haskellState HaskellAction HaskellEditor.otherActions
        state
    ]

  otherActions Simulation =
    [ renderSubmodule _simulationState SimulationAction
        (const Simulation.otherActions)
        state
    ]

  otherActions JSEditor =
    [ renderSubmodule _javascriptState JavascriptAction JSEditor.otherActions
        state
    ]

  otherActions MarloweEditor =
    [ renderSubmodule _marloweEditorState MarloweEditorAction
        MarloweEditor.otherActions
        state
    ]

  otherActions BlocklyEditor =
    [ renderSubmodule _blocklyEditorState BlocklyEditorAction
        BlocklyEditor.otherActions
        state
    ]

  otherActions _ = []

  globalLoadingOverlay =
    if hasGlobalLoading state then
      div
        [ classNames
            [ "loading-overlay", "text-3xl", "font-semibold", "text-white" ]
        ]
        [ div [ classNames [ "mb-small" ] ] [ text "Loading..." ]
        , div_ [ icon Spinner ]
        ]
    else
      text ""

menuBar :: forall p. State -> HTML p Action
menuBar state =
  div [ classNames [ "menu-bar" ] ]
    $ AB.unsafeBuild
    $ menuButton (OpenModal NewProject) "New Project"
        :> gistModal (OpenModal OpenProject) "Open"
        :> menuButton (OpenModal OpenDemo) "Open Example"
        :> menuButton (OpenModal RenameProject) "Rename"
        :> gistModal
          ( if isNothing $ state ^. _gistId then OpenModal SaveProjectAs
            else GistAction PublishOrUpdateGist
          )
          "Save"
        :> gistModal (OpenModal SaveProjectAs) "Save As..."
        :> mempty
  where
  menuButton action name =
    a [ onClick $ const action ]
      [ span [] [ text name ]
      ]

  gistModal action name =
    if
      has (_authStatus <<< _Success <<< authStatusAuthRole <<< _GithubUser)
        state then
      menuButton action name
    else
      menuButton (OpenModal $ GithubLogin action) name
