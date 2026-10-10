-- See Test/Hspec.hs.
module Test.Hspec.Runner (Config (..), defaultConfig, hspecWith) where

import Test.Hspec (Spec, hspec)

data Config = Config { configFailFast :: Bool }

defaultConfig :: Config
defaultConfig = Config { configFailFast = False }

hspecWith :: Config -> Spec -> IO ()
hspecWith _ = hspec
