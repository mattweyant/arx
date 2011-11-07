{-# LANGUAGE OverloadedStrings
           , TypeFamilies
           , StandaloneDeriving #-}

module System.Posix.ARX.Programs where

import Control.Applicative
import Control.Monad
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as Bytes
import qualified Data.ByteString.Lazy as LazyB
import Data.Monoid
import Data.Word

import qualified Blaze.ByteString.Builder as Blaze
import qualified Codec.Compression.BZip as BZip

import System.Posix.ARX.BlazeIsString -- Most string literals are builders.
import System.Posix.ARX.HEREDat
import qualified System.Posix.ARX.Sh as Sh
import qualified System.Posix.ARX.TMPXTools as TMPXTools
import System.Posix.ARX.Tar


{-| ARX subprograms process some input to produce a script.
 -}
class ARX program where
  type Input program        ::  *
  interpret                 ::  program -> Input program -> Blaze.Builder


{-| An 'SHDAT' program processes byte streams with the specified chunking to
    produce a script.
 -}
newtype SHDAT                =  SHDAT Word  -- ^ Chunk size.
instance ARX SHDAT where
  type Input SHDAT           =  LazyB.ByteString
  interpret (SHDAT w) bytes  =  mconcat (chunked bytes)
   where
    chunkSize                =  min (fromIntegral w) maxBound
    chunked input            =  case LazyB.splitAt chunkSize input of
      ("", "")              ->  []
      (a , "")              ->  [chunkIt a]
      (a ,  b)              ->  chunkIt a : chunked b
     where  
      chunkIt                =  script . chunk . mconcat . LazyB.toChunks


{-| A 'TMPX' program archives streams to produce a script that unpacks the
    file data in a temporary location and runs the command with the attached
    environment information in that location. The command may be any
    executable file contents, modulo architectural compatibility. It is
    written along side the temporary work location, to ensure it does not
    collide with any files in the archive.
 -}
data TMPX = TMPX SHDAT LazyB.ByteString -- ^ Code of task to run.
                       [(Sh.Var, Sh.Val)] -- ^ Environment mapping.
                       Bool -- ^ Destroy tmp if task runs successfully.
                       Bool -- ^ Destroy tmp if task exits with an error code.
instance ARX TMPX where
  type Input TMPX            =  [(Tar, LazyB.ByteString)]
  interpret (TMPX encoder run env rm0 rm1) stuff = TMPXTools.render
    (TMPXTools.Template rm0 rm1 env' run' archives)
   where
    archives                 =  mconcat (uncurry archive <$> stuff)
    archive tar bytes        =  mconcat
      ["{\n", shdat bytes, "} | tar ", flags tar, "\n"]
    flags TAR                =  "-x"
    flags TGZ                =  "-x -z"
    flags TBZ                =  "-x -j"
    run'                     =  (shdat . BZip.compress) run
    env' = (shdat . BZip.compress . Blaze.toLazyByteString . Sh.render) env
    shdat                    =  interpret encoder
