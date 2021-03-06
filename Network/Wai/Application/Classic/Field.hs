{-# LANGUAGE OverloadedStrings #-}

module Network.Wai.Application.Classic.Field where

import Control.Arrow (first)
import Control.Monad (mplus)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS hiding (pack)
import Data.ByteString.Char8 as BS (pack)
import qualified Data.Map as Map (toList)
import Data.Maybe
import Data.StaticHash (StaticHash)
import Data.List (delete)
import qualified Data.StaticHash as SH
import qualified Data.Text as T
import Network.HTTP.Date
import Network.HTTP.Types
import Network.Mime (defaultMimeMap, defaultMimeType, MimeType)
import Network.Wai
import Network.Wai.Application.Classic.Header
import Network.Wai.Application.Classic.Lang
import Network.Wai.Application.Classic.Types
import Network.Wai.Logger.Utils
import System.Date.Cache

----------------------------------------------------------------

languages :: Request -> [ByteString]
languages req = maybe [] parseLang $ lookupRequestField hAcceptLanguage req

ifModifiedSince :: Request -> Maybe HTTPDate
ifModifiedSince = lookupAndParseDate hIfModifiedSince

ifUnmodifiedSince :: Request -> Maybe HTTPDate
ifUnmodifiedSince = lookupAndParseDate hIfUnmodifiedSince

ifRange :: Request -> Maybe HTTPDate
ifRange = lookupAndParseDate hIfRange

lookupAndParseDate :: HeaderName -> Request -> Maybe HTTPDate
lookupAndParseDate key req = lookupRequestField key req >>= parseHTTPDate

----------------------------------------------------------------

textPlainHeader :: ResponseHeaders
textPlainHeader = [(hContentType,"text/plain")]

textHtmlHeader :: ResponseHeaders
textHtmlHeader = [(hContentType,"text/html")]

locationHeader :: ByteString -> ResponseHeaders
locationHeader url = [(hLocation, url)]

addServer :: ClassicAppSpec -> ResponseHeaders -> ResponseHeaders
addServer cspec hdr = (hServer, softwareName cspec) : hdr

-- FIXME: the case where "Via:" already exists
addVia :: ClassicAppSpec -> Request -> ResponseHeaders -> ResponseHeaders
addVia cspec req hdr = (hVia, val) : hdr
  where
    ver = httpVersion req
    val = BS.concat [
        showBS (httpMajor ver)
      , "."
      , showBS (httpMinor ver)
      , " "
      , serverName req
      , " ("
      , softwareName cspec
      , ")"
      ]

deleteTransferEncoding :: ResponseHeaders -> ResponseHeaders
deleteTransferEncoding hdr = delete ("Transfer-Encoding", "chunked") hdr

addForwardedFor :: Request -> ResponseHeaders -> ResponseHeaders
addForwardedFor req hdr = (hXForwardedFor, addr) : hdr
  where
    addr = BS.pack . showSockAddr . remoteHost $ req

addLength :: Integer -> ResponseHeaders -> ResponseHeaders
addLength len hdr = (hContentLength, BS.pack (show len)) : hdr

newHeader :: Bool -> ByteString -> ByteString -> ResponseHeaders
newHeader ishtml file date
  | ishtml    = lastMod : textHtmlHeader
  | otherwise = lastMod : (hContentType, mimeType file) : []
  where
    lastMod = (hLastModified, date)

mimeType :: ByteString -> MimeType
mimeType file =fromMaybe defaultMimeType . foldr1 mplus . map lok $ targets
  where
    targets = extensions file
    lok x = SH.lookup x defaultMimeTypes'

extensions :: ByteString -> [ByteString]
extensions file = exts
  where
    entire = case BS.breakByte 46 file of -- '.'
        (_,"") -> ""
        (_,x)  -> BS.tail x
    exts = if entire == "" then [] else entire : BS.split 46 file

defaultMimeTypes' :: StaticHash ByteString MimeType
defaultMimeTypes' = SH.fromList $ map (first (BS.pack . T.unpack)) $ Map.toList defaultMimeMap

addDate :: DateCacheGetter -> ResponseHeaders -> IO ResponseHeaders
addDate zdater hdr = do
    date <- zdater
    return $ (hDate,date) : hdr

addContentRange :: Integer -> Integer -> Integer -> ResponseHeaders -> ResponseHeaders
addContentRange off len size hdr = (hContentRange, val) : hdr
  where
    val = BS.concat [
        "bytes "
      , showBS off
      , "-"
      , showBS (off + len - 1)
      , "/"
      , showBS size
      ]

showBS :: Show a => a -> ByteString
showBS = BS.pack . show
