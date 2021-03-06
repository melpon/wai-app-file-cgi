module Network.Wai.Application.Classic.FileInfo where

import Data.ByteString (ByteString)
import Network.HTTP.Date
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Application.Classic.Field
import Network.Wai.Application.Classic.Header
import Network.Wai.Application.Classic.Path
import Network.Wai.Application.Classic.Range
import Network.Wai.Application.Classic.Types

----------------------------------------------------------------

data StatusAux = Full Status | Partial Integer Integer deriving Show

ifmodified :: Request -> Integer -> HTTPDate -> Maybe StatusAux
ifmodified req size mtime = do
    date <- ifModifiedSince req
    if date /= mtime
       then unconditional req size mtime
       else Just (Full notModified304)

ifunmodified :: Request -> Integer -> HTTPDate -> Maybe StatusAux
ifunmodified req size mtime = do
    date <- ifUnmodifiedSince req
    if date == mtime
       then unconditional req size mtime
       else Just (Full preconditionFailed412)

ifrange :: Request -> Integer -> HTTPDate -> Maybe StatusAux
ifrange req size mtime = do
    date <- ifRange req
    rng  <- lookupRequestField hRange req
    if date == mtime
       then range size rng
       else Just (Full ok200)

unconditional :: Request -> Integer -> HTTPDate -> Maybe StatusAux
unconditional req size _ =
    maybe (Just (Full ok200)) (range size) $ lookupRequestField hRange req

range :: Integer -> ByteString -> Maybe StatusAux
range size rng = case skipAndSize rng size of
  Nothing         -> Just (Full requestedRangeNotSatisfiable416)
  Just (skip,len) -> Just (Partial skip len)

----------------------------------------------------------------

pathinfoToFilePath :: Request -> FileRoute -> Path
pathinfoToFilePath req filei = path'
  where
    path = fromByteString $ rawPathInfo req
    src = fileSrc filei
    dst = fileDst filei
    path' = dst </> (path <\> src)

addIndex :: FileAppSpec -> Path -> Path
addIndex spec path
  | hasTrailingPathSeparator path = path </> indexFile spec
  | otherwise                     = path

redirectPath :: FileAppSpec -> Path -> Maybe Path
redirectPath spec path
  | hasTrailingPathSeparator path = Nothing
  | otherwise                     = Just (path </> indexFile spec)
