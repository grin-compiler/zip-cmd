# zip-cmd
Simple CLI tool for the Haskell [zip](https://hackage.haskell.org/package/zip) library

Run: `./zip-cmd -h`

```
zip-cmd -h
Usage: zip-cmd [COMMAND] [-v|--version]

Available options:
  -h,--help                Show this help text
  -v,--version             Show program version.

Available commands:
  CreateArchive            Create a new archive given its location. This will
                           silently overwrite the specified file if it already
                           exists.
  WithArchive              Work with an existing archive.
  DoesEntryExist           Check whether the specified entry exists in the
                           archive.
  GetEntry                 Get contents of a specific archive entry as a strict
                           ByteString. It's not recommended to use this on big
                           entries, because it will suck out a lot of memory.
  SaveEntry                Save a specific archive entry as a file in the file
                           system.
  CheckEntry               Calculate CRC32 check sum and compare it with the
                           value read from the archive. The function returns
                           True when the check sums are the same—that is, the
                           data is not corrupted.
  UnpackInto               Unpack the archive into the specified directory. The
                           directory will be created if it does not exist.
  GetArchiveComment        Get the archive comment.
  GetArchiveDescription    Get the archive description record.
  AddEntry                 Add a new entry to the archive given its contents in
                           binary form.
  LoadEntry                Load an entry from a given file.
  CopyEntry                Copy an entry “as is” from another zip archive.
  PackDirRecur             Add an directory to the archive. Please note that due
                           to the design of the library, empty sub-directories
                           will not be added.
  RenameEntry              Rename an entry in the archive. If the entry does not
                           exist, nothing will happen.
  DeleteEntry              Delete an entry from the archive, if it does not
                           exist, nothing will happen.
  Recompress               Change compression method of an entry, if it does not
                           exist, nothing will happen.
  SetEntryComment          Set an entry comment, if that entry does not exist,
                           nothing will happen. Note that if binary
                           representation of the comment is longer than 65535
                           bytes, it will be truncated on writing.
  DeleteEntryComment       Delete an entry's comment, if that entry does not
                           exist, nothing will happen.
  SetModTime               Set the last modification date/time. The specified
                           entry may be missing, in that case the action has no
                           effect.
  AddExtraField            Add an extra field. The specified entry may be
                           missing, in that case this action has no effect.
  DeleteExtraField         Delete an extra field by its type (tag). The
                           specified entry may be missing, in that case this
                           action has no effect.
  SetExternalFileAttrs     Set external file attributes. This function can be
                           used to set file permissions.
  SetArchiveComment        Set the comment of the entire archive.
  DeleteArchiveComment     Delete the archive's comment if it's present.
  RunZipCommandsFromFile   Executes zip commands from file.
```
