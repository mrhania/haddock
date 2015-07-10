{-# LANGUAGE FlexibleContexts #-}


module Haddock.Backends.Xhtml.Specialize (specialize) where


import Haddock.Syb

import GHC

import Data.Data


specialize :: (Eq name, Typeable name)
           => Data a
           => name -> HsType name -> a -> a
specialize name details = everywhere (mkT $ specialize' name details)

specialize' :: Eq name => name -> HsType name -> HsType name -> HsType name
specialize' name details (HsTyVar name') | name == name' = details
specialize' _ _ typ = typ
