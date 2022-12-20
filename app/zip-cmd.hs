{-# language LambdaCase, RecordWildCards #-}
import Control.Monad
import Control.Monad.IO.Class
import Options.Applicative
import Options.Applicative.Extra
import Data.Version
import Data.List
import Data.Text (Text)
import Data.ByteString (ByteString)
import System.FilePath
import Codec.Archive.Zip
import Data.Time.Clock
import Data.Word
import qualified ShellWords
import qualified Paths_zip_cmd as ZipCmd

data ZipCommand
  = CreateArchive
    { zipPath :: FilePath
    }
  | WithArchive
    { zipPath :: FilePath
    }
  | DoesEntryExist
    { entryPath :: FilePath
    }
  | GetEntry
    { entryPath :: FilePath
    }
  | SaveEntry
    { entryPath   :: FilePath
    , targetPath  :: FilePath
    }
  | CheckEntry
    { entryPath :: FilePath
    }
  | UnpackInto
    { targetPath :: FilePath
    }
  | GetArchiveComment
  | GetArchiveDescription
  | AddEntry
    { compressionMethod :: CompressionMethod
    , entryContent      :: ByteString
    , entryPath         :: FilePath
    }
  | LoadEntry
    { compressionMethod :: CompressionMethod
    , entryPath         :: FilePath
    , sourcePath        :: FilePath
    }
  | CopyEntry
    { zipPath     :: FilePath
    , sourcePath  :: FilePath
    , targetPath  :: FilePath
    }
  | PackDirRecur
    { compressionMethod :: CompressionMethod
    , sourcePath        :: FilePath
    , entryPathPrefix   :: Maybe FilePath
    }
  | RenameEntry
    { sourcePath  :: FilePath
    , targetPath  :: FilePath
    }
  | DeleteEntry
    { entryPath :: FilePath
    }
  | Recompress
    { compressionMethod :: CompressionMethod
    , entryPath         :: FilePath
    }
  | SetEntryComment
    { comment   :: Text
    , entryPath :: FilePath
    }
  | DeleteEntryComment
    { entryPath :: FilePath
    }
  | SetModTime
    { time      :: UTCTime
    , entryPath :: FilePath
    }
  | AddExtraField
    { tag       :: Word16
    , body      :: ByteString
    , entryPath :: FilePath
    }
  | DeleteExtraField
    { tag       :: Word16
    , entryPath :: FilePath
    }
  | SetExternalFileAttrs
    { attributes  :: Word32
    , entryPath   :: FilePath
    }
  | SetArchiveComment
    { comment :: Text
    }
  | DeleteArchiveComment
  | RunZipCommandsFromFile
    { commandsPath :: FilePath
    }
  deriving Show

evalCommand :: ZipCommand -> ZipArchive ()
evalCommand = \case
  DoesEntryExist{..}        -> join (doesEntryExist <$> mkEntrySelector entryPath) >>= liftIO . print
  GetEntry{..}              -> join (getEntry <$> mkEntrySelector entryPath) >>= liftIO . print
  SaveEntry{..}             -> join (saveEntry <$> mkEntrySelector entryPath <*> pure targetPath)
  CheckEntry{..}            -> join (checkEntry <$> mkEntrySelector entryPath) >>= liftIO . print
  UnpackInto{..}            -> unpackInto targetPath
  GetArchiveComment         -> getArchiveComment >>= maybe (pure ()) (liftIO . print)
  GetArchiveDescription     -> getArchiveDescription >>= liftIO . print
  AddEntry{..}              -> join (addEntry compressionMethod entryContent <$> mkEntrySelector entryPath)
  LoadEntry{..}             -> join (loadEntry compressionMethod <$> mkEntrySelector entryPath <*> pure sourcePath)
  CopyEntry{..}             -> join (copyEntry zipPath <$> mkEntrySelector sourcePath <*> mkEntrySelector targetPath)
  PackDirRecur{..}          -> packDirRecur compressionMethod (\p -> mkEntrySelector $ maybe p (</> p) entryPathPrefix) sourcePath
  RenameEntry{..}           -> join (renameEntry <$> mkEntrySelector sourcePath <*> mkEntrySelector targetPath)
  DeleteEntry{..}           -> join (deleteEntry <$> mkEntrySelector entryPath)
  Recompress{..}            -> join (recompress compressionMethod <$> mkEntrySelector entryPath)
  SetEntryComment{..}       -> join (setEntryComment comment <$> mkEntrySelector entryPath)
  DeleteEntryComment{..}    -> join (deleteEntryComment <$> mkEntrySelector entryPath)
  SetModTime{..}            -> join (setModTime time <$> mkEntrySelector entryPath)
  AddExtraField{..}         -> join (addExtraField tag body <$> mkEntrySelector entryPath)
  DeleteExtraField{..}      -> join (deleteExtraField tag <$> mkEntrySelector entryPath)
  SetExternalFileAttrs{..}  -> join (setExternalFileAttrs attributes <$> mkEntrySelector entryPath)
  SetArchiveComment{..}     -> setArchiveComment comment
  DeleteArchiveComment      -> deleteArchiveComment

evalCmdZipArchive :: [ZipCommand] -> ZipArchive [ZipCommand]
evalCmdZipArchive cmds = case cmds of
  []                  -> pure []
  CreateArchive{} : _ -> pure cmds
  WithArchive{} : _   -> pure cmds
  RunZipCommandsFromFile{..} : cs -> do
    cmdList <- liftIO $ readCommandsFromFile commandsPath
    evalCmdZipArchive $ cmdList ++ cs
  c : cs -> do
    evalCommand c
    evalCmdZipArchive cs

evalCmdIO :: [ZipCommand] -> IO ()
evalCmdIO = \case
  CreateArchive{..} : cmds -> do
    remainingCmds <- createArchive zipPath (evalCmdZipArchive cmds)
    evalCmdIO remainingCmds
  WithArchive{..} : cmds -> do
    remainingCmds <- withArchive zipPath (evalCmdZipArchive cmds)
    evalCmdIO remainingCmds
  RunZipCommandsFromFile{..} : cmds -> do
    cmdList <- readCommandsFromFile commandsPath
    evalCmdIO $ cmdList ++ cmds
  c : cmds -> do
    putStrLn $ "ignore: " ++ show c
    evalCmdIO cmds
  [] -> pure ()

readCommandsFromFile :: FilePath -> IO [ZipCommand]
readCommandsFromFile fname = do
  args <- ShellWords.parse <$> readFile fname >>= \case
    Right a   -> pure a
    Left err  -> fail err
  handleParseResult $ execParserPure defaultPrefs opts args

compressionMethods :: String
compressionMethods = intercalate "|" $ map show ([minBound..maxBound] :: [CompressionMethod])

zipCommand :: Parser ZipCommand
zipCommand = hsubparser $ mconcat
  [ command "CreateArchive"
    (info
      (CreateArchive
        <$> strOption (long "zipPath" <> metavar "FILENAME" <> help "Location of the archive file to create")
      )
      (progDesc "Create a new archive given its location. This will silently overwrite the specified file if it already exists.")
    )
  , command "WithArchive"
    (info
      (WithArchive
        <$> strOption (long "zipPath" <> metavar "FILENAME" <> help "Location of the archive to work with")
      )
      (progDesc "Work with an existing archive.")
    )
  , command "DoesEntryExist"
    (info
      (DoesEntryExist
        <$> strOption (long "entryPath" <> metavar "FILENAME" <> help "Selector that identifies archive entry")
      )
      (progDesc "Check whether the specified entry exists in the archive.")
    )
  , command "GetEntry"
    (info
      (GetEntry
        <$> strOption (long "entryPath" <> metavar "FILENAME" <> help "Selector that identifies archive entry")
      )
      (progDesc "Get contents of a specific archive entry as a strict ByteString. It's not recommended to use this on big entries, because it will suck out a lot of memory.")
    )
  , command "SaveEntry"
    (info
      (SaveEntry
        <$> strOption (long "entryPath" <> metavar "FILENAME" <> help "Selector that identifies archive entry")
        <*> strOption (long "targetPath" <> metavar "FILENAME" <> help "Where to save the file")
      )
      (progDesc "Save a specific archive entry as a file in the file system.")
    )
  , command "CheckEntry"
    (info
      (CheckEntry
        <$> strOption (long "entryPath" <> metavar "FILENAME" <> help "Selector that identifies archive entry")
      )
      (progDesc "Calculate CRC32 check sum and compare it with the value read from the archive. The function returns True when the check sums are the same—that is, the data is not corrupted.")
    )
  , command "UnpackInto"
    (info
      (UnpackInto
        <$> strOption (long "targetPath" <> metavar "DIRNAME" <> help "Where to unpack the archive")
      )
      (progDesc "Unpack the archive into the specified directory. The directory will be created if it does not exist.")
    )
  , command "GetArchiveComment"
    (info
      (pure GetArchiveComment)
      (progDesc "Get the archive comment.")
    )
  , command "GetArchiveDescription"
    (info
      (pure GetArchiveDescription)
      (progDesc "Get the archive description record.")
    )
  , command "AddEntry"
    (info
      (AddEntry
        <$> option auto (long "compressionMethod" <> metavar compressionMethods <> help "The compression method to use")
        <*> strOption (long "entryContent" <> metavar "BYTESTRING" <> help "Entry contents")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to add")
      )
      (progDesc "Add a new entry to the archive given its contents in binary form.")
    )
  , command "LoadEntry"
    (info
      (LoadEntry
        <$> option auto (long "compressionMethod" <> metavar compressionMethods <> help "The compression method to use")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to add")
        <*> strOption (long "sourcePath" <> metavar "FILENAME" <> help "Path to the file to add")
      )
      (progDesc "Load an entry from a given file.")
    )
  , command "CopyEntry"
    (info
      (CopyEntry
        <$> strOption (long "zipPath" <> metavar "FILENAME" <> help "Path to the archive to copy from")
        <*> strOption (long "sourcePath" <> metavar "FILENAME" <> help "Name of the entry (in the source archive) to copy")
        <*> strOption (long "targetPath" <> metavar "FILENAME" <> help "Name of the entry to insert (in current archive)")
      )
      (progDesc "Copy an entry “as is” from another zip archive.")
    )
  , command "PackDirRecur"
    (info
      (PackDirRecur
        <$> option auto (long "compressionMethod" <> metavar compressionMethods <> help "The compression method to use")
        <*> strOption (long "sourcePath" <> metavar "FILENAME" <> help "Path to the directory to add")
        <*> optional (strOption (long "entryPathPrefix" <> metavar "DIRNAME" <> help "Path prefix of the entries in the archive"))
      )
      (progDesc "Add an directory to the archive. Please note that due to the design of the library, empty sub-directories will not be added.")
    )
  , command "RenameEntry"
    (info
      (RenameEntry
        <$> strOption (long "sourcePath" <> metavar "FILENAME" <> help "The original entry name")
        <*> strOption (long "targetPath" <> metavar "FILENAME" <> help "The new entry name")
      )
      (progDesc "Rename an entry in the archive. If the entry does not exist, nothing will happen.")
    )
  , command "DeleteEntry"
    (info
      (DeleteEntry
        <$> strOption (long "entryPath" <> metavar "FILENAME" <> help "Selector that identifies archive entry")
      )
      (progDesc "Delete an entry from the archive, if it does not exist, nothing will happen.")
    )
  , command "Recompress"
    (info
      (Recompress
        <$> option auto (long "compressionMethod" <> metavar compressionMethods <> help "The new compression method")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to re-compress")
      )
      (progDesc "Change compression method of an entry, if it does not exist, nothing will happen.")
    )
  , command "SetEntryComment"
    (info
      (SetEntryComment
        <$> strOption (long "comment" <> metavar "TEXT" <> help "Text of the comment")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to comment on")
      )
      (progDesc "Set an entry comment, if that entry does not exist, nothing will happen. Note that if binary representation of the comment is longer than 65535 bytes, it will be truncated on writing.")
    )
  , command "DeleteEntryComment"
    (info
      (DeleteEntryComment
        <$> strOption (long "entryPath" <> metavar "FILENAME" <> help "Selector that identifies archive entry")
      )
      (progDesc "Delete an entry's comment, if that entry does not exist, nothing will happen.")
    )
  , command "SetModTime"
    (info
      (SetModTime
        <$> option auto (long "time" <> metavar "UTCTime" <> help "New modification time")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to modify")
      )
      (progDesc "Set the last modification date/time. The specified entry may be missing, in that case the action has no effect.")
    )
  , command "AddExtraField"
    (info
      (AddExtraField
        <$> option auto (long "tag" <> metavar "WORD16" <> help "Tag (header id) of the extra field to add")
        <*> strOption (long "body" <> metavar "BYTESTRING" <> help "Body of the field")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to modify")
      )
      (progDesc "Add an extra field. The specified entry may be missing, in that case this action has no effect.")
    )
  , command "DeleteExtraField"
    (info
      (DeleteExtraField
        <$> option auto (long "tag" <> metavar "WORD16" <> help "Tag (header id) of the extra field to delete")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to modify")
      )
      (progDesc "Delete an extra field by its type (tag). The specified entry may be missing, in that case this action has no effect.")
    )
  , command "SetExternalFileAttrs"
    (info
      (SetExternalFileAttrs
        <$> option auto (long "attributes" <> metavar "WORD32" <> help "External file attributes")
        <*> strOption (long "entryPath" <> metavar "FILENAME" <> help "Name of the entry to modify")
      )
      (progDesc "Set external file attributes. This function can be used to set file permissions.")
    )
  , command "SetArchiveComment"
    (info
      (SetArchiveComment
        <$> strOption (long "comment" <> metavar "TEXT" <> help "Text of the comment")
      )
      (progDesc "Set the comment of the entire archive.")
    )
  , command "DeleteArchiveComment"
    (info
      (pure DeleteArchiveComment)
      (progDesc "Delete the archive's comment if it's present.")
    )
  , command "RunZipCommandsFromFile"
    (info
      (RunZipCommandsFromFile
        <$> strOption (long "commandsPath" <> metavar "FILENAME" <> help "Location of the zip commands file to execute")
      )
      (progDesc "Executes zip commands from file.")
    )
  ]

{-
TODO:
  - support regex patterns for filtering (i.e. unpack only the selected content)
-}

version :: Parser (a -> a)
version = option (readerAbort versionMsg) $
  mconcat
    [ help "Show program version."
    , long "version"
    , short 'v'
    , noArgError versionMsg
    , value id
    , metavar ""
    ]
  where
    versionMsg = InfoMsg . showVersion $ ZipCmd.version

opts :: ParserInfo [ZipCommand]
opts = info (many zipCommand <**> helper <**> version) fullDesc

main :: IO ()
main = do
  cmds <- execParser opts
  evalCmdIO cmds
