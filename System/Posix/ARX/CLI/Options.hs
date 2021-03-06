{-# LANGUAGE OverloadedStrings
           , TupleSections
           , StandaloneDeriving #-}

module System.Posix.ARX.CLI.Options where

import Control.Applicative hiding (many)
import Control.Monad
import Data.ByteString (ByteString)
import qualified Data.ByteString as Bytes
import qualified Data.ByteString.Char8 as Char8
import Data.Either
import Data.List
import Data.Maybe
import Data.Ord
import Data.Word
import Text.Parsec hiding (satisfy, (<|>))

import qualified Data.Attoparsec

import System.Posix.ARX.CLI.CLTokens (Class(..))
import qualified System.Posix.ARX.CLI.CLTokens as CLTokens
import qualified System.Posix.ARX.Sh as Sh


shdat                       ::  ArgsParser ([Word], [IOStream], [IOStream])
shdat                        =  do
  arg "shdat"
  coalesce <$> manyTill (_1 blockSize <|> _2 outputFile <|> _3 ioStream) eof
 where
  _1                         =  ((,Nothing,Nothing) . Just <$>)
  _2                         =  ((Nothing,,Nothing) . Just <$>)
  _3                         =  ((Nothing,Nothing,) . Just <$>)
  coalesce                   =  foldr f ([], [], [])
   where
    f (Just a, _, _) (as, bs, cs) = (a:as, bs, cs)
    f (_, Just b, _) (as, bs, cs) = (as, b:bs, cs)
    f (_, _, Just c) (as, bs, cs) = (as, bs, c:cs)
    f _ stuff                =  stuff

tmpx :: ArgsParser ( [Word], [IOStream], [IOStream], [(Sh.Var, Sh.Val)],
                     [(Bool, Bool)], [ByteSource]                        )
tmpx                         =  do
  arg "tmpx"
  bars                      <-  (try . lookAhead) slashes
  coalesce <$> case bars of
                 Nothing    ->  flags eof
                 Just bars  ->  do let eof_bars = () <$ arg bars <|> eof
                                   before <- flags eof_bars
                                   cmd <- _6 (gather eof_bars)
                                   after <- flags eof
                                   return (before ++ (cmd:after))
 where
  flags                      =  manyTill flag
  gather = (ByteString . Char8.unwords <$>) . manyTill anyArg
  flag                       =  _1 blockSize <|> _2 outputFile <|> _3 ioStream
                            <|> _4 env       <|> _5 rm   <|> _6 scriptToRun
  _1 = ((,Nothing,Nothing,Nothing,Nothing,Nothing) . Just <$>)
  _2 = ((Nothing,,Nothing,Nothing,Nothing,Nothing) . Just <$>)
  _3 = ((Nothing,Nothing,,Nothing,Nothing,Nothing) . Just <$>)
  _4 = ((Nothing,Nothing,Nothing,,Nothing,Nothing) . Just <$>)
  _5 = ((Nothing,Nothing,Nothing,Nothing,,Nothing) . Just <$>)
  _6 = ((Nothing,Nothing,Nothing,Nothing,Nothing,) . Just <$>)
  coalesce                   =  foldr f ([], [], [], [], [], [])
   where
    f (Just a, _, _, _, _, _)   (as, bs, cs, ds, es, fs)
                             =  (a:as, bs, cs, ds, es, fs)
    f (_, Just b, _, _, _, _)   (as, bs, cs, ds, es, fs)
                             =  (as, b:bs, cs, ds, es, fs)
    f (_, _, Just c, _, _, _)   (as, bs, cs, ds, es, fs)
                             =  (as, bs, c:cs, ds, es, fs)
    f (_, _, _, Just d, _, _)   (as, bs, cs, ds, es, fs)
                             =  (as, bs, cs, d:ds, es, fs)
    f (_, _, _, _, Just e, _)   (as, bs, cs, ds, es, fs)
                             =  (as, bs, cs, ds, e:es, fs)
    f (_, _, _, _, _, Just f)   (as, bs, cs, ds, es, fs)
                             =  (as, bs, cs, ds, es, f:fs)
    f _ stuff                =  stuff

blockSize                   ::  ArgsParser Word
blockSize                    =  do arg "-b"
                                   CLTokens.sizeBounded <@> tokCL Size

outputFile                  ::  ArgsParser IOStream
outputFile                   =  arg "-o" >> ioStream

ioStream                    ::  ArgsParser IOStream
ioStream                     =  STDIO <$  tokCL Dash
                            <|> Path  <$> tokCL QualifiedPath

qPath                       ::  ArgsParser ByteString
qPath                        =  tokCL QualifiedPath

rm                          ::  ArgsParser (Bool, Bool)
rm  =   (True,  False) <$ arg "-rm0"  <|>  (False, True) <$ arg "-rm1"
   <|>  (False, False) <$ arg "-rm!"  <|>  (True,  True) <$ arg "-rm_"

env                         ::  ArgsParser (Sh.Var, Sh.Val)
env                          =  do
  (var, assignment)         <-  Char8.break (== '=') <$> tokCL EnvBinding
  case (,) <$> Sh.var var <*> Sh.val (Bytes.drop 1 assignment) of
    Nothing                 ->  mzero
    Just x                  ->  return x

scriptToRun                 ::  ArgsParser ByteSource
scriptToRun                  =  arg "-e" >> IOStream <$> ioStream

cmd                         ::  ByteString -> ArgsParser ByteSource
cmd bars = ByteString . Char8.unwords <$> bracketed bars bars anyArg
 where
  bracketed start end p      =  arg start >> manyTill p (eof <|> () <$ arg end)


{-| A byte-oriented store that can be read from or written to in a streaming
    fashion.
 -}
data IOStream                =  STDIO | Path !ByteString
deriving instance Eq IOStream
deriving instance Ord IOStream
deriving instance Show IOStream

{-| A source of bytes (no writing, only reading).
 -}
data ByteSource              =  ByteString !ByteString | IOStream !IOStream
deriving instance Eq ByteSource
deriving instance Ord ByteSource
deriving instance Show ByteSource


type ArgsParser              =  Parsec [ByteString] ()

satisfy                     ::  (ByteString -> Bool) -> ArgsParser ByteString
satisfy p                    =  argPrim test
 where
  test b                     =  guard (p b) >> Just b

anyArg                      ::  ArgsParser ByteString
anyArg                       =  argPrim Just

arg                         ::  ByteString -> ArgsParser ByteString
arg b                        =  satisfy (== b)

argPrim                     ::  (ByteString -> Maybe t) -> ArgsParser t
argPrim                      =  tokenPrim show next
 where
  next pos _ _               =  incSourceLine pos 1

(<@>) :: Data.Attoparsec.Parser t -> ArgsParser ByteString -> ArgsParser t
atto <@> parsec              =  do
  res                       <-  Data.Attoparsec.parseOnly atto <$> parsec
  case res of Left _        ->  mzero
              Right x       ->  return x
infixl 4 <@>

tokCL                       ::  Class -> ArgsParser ByteString
tokCL tokenClass             =  satisfy (CLTokens.match tokenClass)

slashes                     ::  ArgsParser (Maybe ByteString)
slashes = listToMaybe . longestFirst . catMaybes <$> manyTill classify eof
 where
  classify                   =  Just <$> satisfy slashRun <|> Nothing <$ anyArg
  longestFirst               =  sortBy (comparing (negate . Bytes.length))
  slashRun s                 =  Char8.all (== '/') s && Bytes.length s > 1

