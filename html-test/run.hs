#!/usr/bin/env runhaskell
{-# LANGUAGE CPP #-}
{-# LANGUAGE RecordWildCards #-}


import Control.Monad

import Data.Maybe

import Distribution.Simple.Utils
import Distribution.Verbosity

import System.Console.GetOpt
import System.Directory
import System.Environment
import System.Exit
import System.FilePath
import System.IO
import System.Process


baseDir, rootDir :: FilePath
baseDir = takeDirectory __FILE__
rootDir = baseDir </> ".."

srcDir, refDir, outDir :: FilePath
srcDir = baseDir </> "src"
refDir = baseDir </> "ref"
outDir = baseDir </> "out"

resDir :: FilePath
resDir = rootDir </> "resources"


data Config = Config
    { cfgHaddockPath :: FilePath
    , cfgGhcPath :: FilePath
    , cfgFiles :: [FilePath]
    }


main :: IO ()
main = do
    Config { .. } <- loadConfig =<< getArgs
    return ()


loadConfig :: [String] -> IO Config
loadConfig args = do
    let (flags, files, errors) = getOpt Permute options args

    when (not $ null errors) $ do
        hPutStr stderr $ concat errors
        exitFailure

    when (FlagHelp `elem` flags) $ do
        hPutStrLn stderr $ usageInfo "" options
        exitSuccess

    env <- Just . (:) ("haddock_datadir", resDir) <$> getEnvironment

    let cfgHaddockPath = flagsHaddockPath flags

    printVersions env cfgHaddockPath

    cfgFiles <- processFileArgs files
    cfgGhcPath <- init <$> rawSystemStdout normal cfgHaddockPath
        ["--print-ghc-path"]

    putStrLn $ "Files to test: " ++ show cfgFiles
    return $ Config { .. }


printVersions :: Maybe [(String, String)] -> FilePath -> IO ()
printVersions env haddockPath = do
    handle <- runProcess' haddockPath $ processConfig
        { pcEnv = env
        , pcArgs = ["--version"]
        }
    waitForSuccess "Failed to run `haddock --version`" handle

    handle <- runProcess' haddockPath $ processConfig
        { pcEnv = env
        , pcArgs = ["--ghc-version"]
        }
    waitForSuccess "Failed to run `haddock --ghc-version`" handle


processFileArgs :: [String] -> IO [FilePath]
processFileArgs [] = filter isSourceFile <$> getDirectoryContents srcDir
processFileArgs args = pure $ map processFileArg args


processFileArg :: String -> FilePath
processFileArg arg
    | isSourceFile arg = arg
    | otherwise = srcDir </> arg <.> "hs"


isSourceFile :: FilePath -> Bool
isSourceFile path = takeExtension path `elem` [".hs", ".lhs"]


data Flag
    = FlagHaddockPath FilePath
    | FlagHelp
    deriving Eq


options :: [OptDescr Flag]
options =
    [ Option [] ["haddock-path"] (ReqArg FlagHaddockPath "FILE")
        "path to Haddock executable to exectue tests with"
    , Option ['h'] ["help"] (NoArg FlagHelp)
        "display this help end exit"
    ]


flagsHaddockPath :: [Flag] -> FilePath
flagsHaddockPath flags =
    case mlast [ path | FlagHaddockPath path <- flags ] of
        Just path -> path
        Nothing -> rootDir </> "dist" </> "build" </> "haddock" </> "haddock"
  where
    mlast = listToMaybe . reverse


data ProcessConfig = ProcessConfig
    { pcArgs :: [String]
    , pcWorkDir :: Maybe FilePath
    , pcEnv :: Maybe [(String, String)]
    , pcStdIn :: Maybe Handle
    , pcStdOut :: Maybe Handle
    , pcStdErr :: Maybe Handle
    }


processConfig :: ProcessConfig
processConfig = ProcessConfig
    { pcArgs = []
    , pcWorkDir = Nothing
    , pcEnv = Nothing
    , pcStdIn = Nothing
    , pcStdOut = Nothing
    , pcStdErr = Nothing
    }


runProcess' :: FilePath -> ProcessConfig -> IO ProcessHandle
runProcess' path (ProcessConfig { .. }) = runProcess
    path pcArgs pcWorkDir pcEnv pcStdIn pcStdOut pcStdErr


waitForSuccess :: String -> ProcessHandle -> IO ()
waitForSuccess msg handle = do
    result <- waitForProcess handle
    unless (result == ExitSuccess) $ do
        hPutStrLn stderr $ msg
        exitFailure
