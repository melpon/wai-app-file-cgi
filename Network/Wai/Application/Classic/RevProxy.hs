{-# LANGUAGE OverloadedStrings #-}

module Network.Wai.Application.Classic.RevProxy (revProxyApp) where

import Blaze.ByteString.Builder (Builder, fromByteString)
import Control.Exception
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as L
import Data.Enumerator (Iteratee, run_, (=$), ($$), ($=), enumList)
import qualified Data.Enumerator.List as EL
import qualified Network.HTTP.Enumerator as H
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Application.Classic.Field
import Network.Wai.Application.Classic.Types
import Network.Wai.Application.Classic.Utils
import Prelude hiding (catch)

{- TODO
 - incremental boy (persist connection)
 - Body
-}

toHTTPRequest :: Request -> RevProxyRoute -> H.Request m
toHTTPRequest req route = H.def {
    H.host = revProxyDomain route
  , H.port = revProxyPort route
  , H.secure = isSecure req
  , H.checkCerts = H.defaultCheckCerts
  , H.requestHeaders = []
  , H.path = path
  , H.queryString = queryString req
  , H.requestBody = H.RequestBodyLBS L.empty -- xxx Ah Ha!
  , H.method = requestMethod req
  , H.proxy = Nothing
  , H.rawBody = False
  , H.decompress = H.alwaysDecompress
  }
  where
    src = revProxySrc route
    dst = revProxyDst route
    path = dst +++ BS.drop (BS.length src) (rawPathInfo req)

{-|
  Relaying any requests as reverse proxy.
  Relaying HTTP body is not implemented yet.
-}

revProxyApp :: ClassicAppSpec -> RevProxyAppSpec -> RevProxyRoute -> Application
revProxyApp cspec spec route req = return $ ResponseEnumerator $ \respBuilder ->
    run_ (H.http (toHTTPRequest req route) (fromBS cspec respBuilder) mgr)
    `catch` badGateway cspec respBuilder
  where
    mgr = revProxyManager spec

fromBS :: ClassicAppSpec
       -> (Status -> ResponseHeaders -> Iteratee Builder IO a)
       -> (Status -> ResponseHeaders -> Iteratee ByteString IO a)
fromBS cspec f s h = EL.map fromByteString -- body: from BS to Builder
            =$ f s h'                -- hedr: removing CE:
  where
    h' = ("Server", softwareName cspec):filter p h
    p ("Content-Encoding", _) = False
    p _ = True

badGateway :: ClassicAppSpec
           -> (Status -> ResponseHeaders -> Iteratee Builder IO a) 
           -> SomeException -> IO a
badGateway cspec builder _ = run_ $ bdy $$ builder status502 hdr
  where
    hdr = addServer cspec textPlainHeader
    bdy = enumList 1 ["Bad Gateway\r\n"] $= EL.map fromByteString