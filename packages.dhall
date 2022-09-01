let mkPackage =
      https://raw.githubusercontent.com/purescript/package-sets/psc-0.13.0-20190626/src/mkPackage.dhall sha256:0b197efa1d397ace6eb46b243ff2d73a3da5638d8d0ac8473e8e4a8fc528cf57

let upstream =
      https://github.com/purescript/package-sets/releases/download/psc-0.15.2-20220706/packages.dhall sha256:7a24ebdbacb2bfa27b2fc6ce3da96f048093d64e54369965a2a7b5d9892b6031

in  upstream
  with js-object =
      mkPackage
        [ "aff"
        , "console"
        , "effect"
        , "prelude"
        , "psci-support"
        , "typelevel-prelude"
        ]
        "https://git@github.com/paluh/purescript-js-object"
        "73db55f89744b032f44c9ec49804f46e3ee63ed7"
  with infinite-lists =
      mkPackage
        [ "console"
        , "control"
        , "effect"
        , "lazy"
        , "maybe"
        , "prelude"
        , "psci-support"
        , "tuples"
        ]
        "https://git@github.com/Thimoteus/purescript-infinite-lists"
        "v3.2.0"
  with markdown =
      mkPackage
        [ "arrays"
        , "assert"
        , "bifunctors"
        , "console"
        , "const"
        , "control"
        , "datetime"
        , "effect"
        , "either"
        , "enums"
        , "foldable-traversable"
        , "functors"
        , "identity"
        , "integers"
        , "lists"
        , "maybe"
        , "newtype"
        , "parsing"
        , "partial"
        , "precise"
        , "prelude"
        , "psci-support"
        , "strings"
        , "tuples"
        , "unfoldable"
        , "unicode"
        , "validation"
        ]
        "https://github.com/input-output-hk/purescript-markdown"
        "3c5536d5cad663c0912bae89205dd1c8934d525b"
  with datetime-iso =
      mkPackage
        [ "aff"
        , "argonaut"
        , "argonaut-codecs"
        , "argonaut-core"
        , "arrays"
        , "bifunctors"
        , "datetime"
        , "effect"
        , "either"
        , "enums"
        , "foldable-traversable"
        , "maybe"
        , "newtype"
        , "parsing"
        , "partial"
        , "prelude"
        , "spec"
        , "strings"
        , "transformers"
        ]
        "https://github.com/input-output-hk/purescript-datetime-iso"
        "a5de49e1e4b75d1731b7ec08e07f94eb6985d452"
  with undefined-or =
    { dependencies = [ "prelude", "control", "maybe" ]
    , repo = "https://github.com/CarstenKoenig/purescript-undefined-or.git"
    , version = "5822ab71acc9ed276afd6fa96f1cb3135e376719"
    }
  with uuid =
    { dependencies =
      [ "prelude", "aff", "effect", "maybe", "partial", "spec", "strings" ]
    , repo = "https://github.com/megamaddu/purescript-uuid.git"
    , version = "v9.0.0"
    }
  with servant-support =
      mkPackage
        [ "aff"
        , "affjax"
        , "argonaut"
        , "arrays"
        , "bifunctors"
        , "either"
        , "http-methods"
        , "maybe"
        , "newtype"
        , "nonempty"
        , "prelude"
        , "psci-support"
        , "strings"
        , "transformers"
        , "tuples"
        , "uri"
        ]
        "https://github.com/input-output-hk/purescript-servant-support"
        "61f85eb0657196d4bfc80ae4736d6a6d9ebd4529"
  with json-helpers =
      mkPackage
        [ "aff"
        , "argonaut-codecs"
        , "argonaut-core"
        , "arrays"
        , "bifunctors"
        , "contravariant"
        , "control"
        , "effect"
        , "either"
        , "enums"
        , "foldable-traversable"
        , "foreign-object"
        , "maybe"
        , "newtype"
        , "ordered-collections"
        , "prelude"
        , "profunctor"
        , "psci-support"
        , "quickcheck"
        , "record"
        , "spec"
        , "spec-quickcheck"
        , "transformers"
        , "tuples"
        , "typelevel-prelude"
        ]
        "https://github.com/input-output-hk/purescript-bridge-json-helpers.git"
        "0ff78186a949722f37218046a09abdf27d77ecfe"
  with halogen-nselect =
      mkPackage
        [ "aff"
        , "effect"
        , "foldable-traversable"
        , "halogen"
        , "maybe"
        , "prelude"
        , "psci-support"
        , "unsafe-coerce"
        , "web-dom"
        , "web-events"
        , "web-html"
        , "web-uievents"
        ]
        "https://github.com/jhbertra/purescript-halogen-nselect"
        "5a7a39e41c3a918a8cf48b24ac87c5cf7e080fe8"
  with unlift =
      mkPackage
        [ "aff"
        , "effect"
        , "either"
        , "identity"
        , "lists"
        , "maybe"
        , "monad-control"
        , "prelude"
        , "transformers"
        , "tuples"
        ]
        "https://github.com/tweag/purescript-unlift"
        "c05bf5f8b29059dc568b34999eb0a5714305076c"
  with marlowe =
      mkPackage
        [ "argonaut"
        , "argonaut-codecs"
        , "argonaut-core"
        , "arrays"
        , "bifunctors"
        , "bigints"
        , "contravariant"
        , "control"
        , "datetime"
        , "either"
        , "foldable-traversable"
        , "foreign-object"
        , "functions"
        , "integers"
        , "json-helpers"
        , "lists"
        , "maybe"
        , "newtype"
        , "ordered-collections"
        , "partial"
        , "prelude"
        , "profunctor-lenses"
        , "strings"
        , "transformers"
        , "tuples"
        , "unfoldable"
        ]
        "https://github.com/input-output-hk/purescript-marlowe"
        "1f5d5606c2deced2363a69a76a1a24a052618c67"
