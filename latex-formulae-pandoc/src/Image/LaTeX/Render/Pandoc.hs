{-# LANGUAGE LambdaCase #-}
module Image.LaTeX.Render.Pandoc
       ( -- * Data URIs
         convertFormulaDataURI
       , convertAllFormulaeDataURI
         -- * Separate Files
       , convertFormulaFiles
       , convertAllFormulaeFiles
         -- ** Name Supplies
       , NameSupply
       , newNameSupply
         -- * Scaling
       , ShrinkSize
       ) where

import Text.Pandoc.Definition
import Text.Pandoc.Walk
import Image.LaTeX.Render
import Codec.Picture
import Control.Applicative
import Data.IORef
import System.FilePath

import qualified Data.ByteString.Base64.Lazy as B64
import qualified Data.ByteString.Lazy.Char8 as BS

dims :: Image a -> (Int,Int)
dims = liftA2 (,) imageWidth imageHeight

dimensions :: DynamicImage -> (Int,Int)
dimensions (ImageRGB8 i)   = dims i
dimensions (ImageRGBA8 i)  = dims i
dimensions (ImageRGB16 i)  = dims i
dimensions (ImageRGBA16 i) = dims i
dimensions (ImageY8 i)     = dims i
dimensions (ImageY16 i)    = dims i
dimensions (ImageYA8 i)    = dims i
dimensions (ImageYA16 i)   = dims i
dimensions _               = error "Unsupported image format somehow!"

-- | Denominator for various dimensions. For high DPI displays, it can be useful to use values of 2 or 4, so that the dimensions
--   of the image are a fraction of the actual image size, and the image appears more crisp. Otherwise, a value of 1 will always
--   produce sensible, if somewhat pixelated results.
type ShrinkSize = Int

-- | Convert a formula in a pandoc document to an image, embedding the image into the HTML using Data URIs.
convertFormulaDataURI
  :: ShrinkSize                   -- ^ Denominator for all dimensions. Useful for displaying high DPI images in small sizes, for retina displays. Otherwise set to 1.
  -> EnvironmentOptions           -- ^ System environment settings
  -> (MathType -> FormulaOptions) -- ^ LaTeX environment settings for each equation type (display and inline)
  -> Inline -> IO Inline
convertFormulaDataURI sh o1 o2 (Math t s) = imageForFormula o1 (o2 t) s >>= \case
   Left e -> return $ Str (show e)
   Right (b,i) -> let
       Right bs = encodeDynamicPng i
       dataUri = "data:image/png;base64," ++ BS.unpack (B64.encode bs)
       (ow,oh) = dimensions i
       (w,h) = (ow `div` sh, oh `div` sh)
     in return $ RawInline (Format "html") $
        "<img width="  ++ show w ++
            " height=" ++ show h ++
            " src=\""  ++ dataUri ++ "\"" ++
            " class="  ++ (case t of InlineMath -> "inline-math"; _ -> "display-math") ++
            " style=\"margin:0; vertical-align:-" ++ show (b `div` sh) ++ "px;\"/>"
convertFormulaDataURI sh o1 o2 x = return x

-- | Convert all formulae in a pandoc document to images, embedding the images into the HTML using Data URIs.
convertAllFormulaeDataURI
  :: ShrinkSize                   -- ^ Denominator for all dimensions. Useful for displaying high DPI images in small sizes, for retina displays. Otherwise set to 1.
  -> EnvironmentOptions           -- ^ System environment settings
  -> (MathType -> FormulaOptions) -- ^ LaTeX environment settings for each equation type (display and inline)
  -> Pandoc -> IO Pandoc
convertAllFormulaeDataURI a b c = walkM $ convertFormulaDataURI a b c 


-- | If we use files for the images, we need some way of naming the image files we produce
--   A NameSupply provides us with a source of unique names via an ever-increasing integer.
--   It's important that any invocation of 'convertFormulaFiles' or 'convertAllFormulaeFiles'
--   that shares the same image storage directory will also use the same name supply, or they
--   will overwrite each others images.
type NameSupply = IORef Int

-- | Create a new name supply.
newNameSupply :: IO NameSupply
newNameSupply = newIORef 0

-- | Convert a formula in a pandoc document to an image, storing the images in a separate directory.
convertFormulaFiles
  :: NameSupply                   -- ^ Unique file name supply. Reuse this for every invocation that shares the same image directory.
  -> FilePath                     -- ^ Name of image directory where images will be stored
  -> ShrinkSize                   -- ^ Denominator for all dimensions. Useful for displaying high DPI images in small sizes, for retina displays. Otherwise set to 1.
  -> EnvironmentOptions           -- ^ System environment settings
  -> (MathType -> FormulaOptions) -- ^ LaTeX environment settings for each equation type (display and inline)
  -> Inline -> IO Inline
convertFormulaFiles ns bn sh o1 o2 (Math t s) = imageForFormula o1 (o2 t) s >>= \case
   Left e -> return $ Str (show e)
   Right (b,i) -> do
     fn <- readIORef ns
     modifyIORef ns (+1)
     let uri = bn </> show fn <.> "png"
         (ow,oh) = dimensions i
         (w,h) = (ow `div` sh, oh `div` sh)
     _ <- writeDynamicPng uri i
     return $ RawInline (Format "html") $
        "<img width="  ++ show w ++
            " height=" ++ show h ++
            " src=\""  ++ uri ++ "\"" ++
            " class="  ++ (case t of InlineMath -> "inline-math"; _ -> "display-math") ++
            " style=\"margin:0; vertical-align:-" ++ show (b `div` sh) ++ "px;\"/>"
convertFormulaFiles _ _ _ _ _ x = return x

-- | Convert every formula in a pandoc document to an image, storing the images in a separate directory.
convertAllFormulaeFiles
  :: NameSupply                   -- ^ Unique file name supply. Reuse this for every invocation that shares the same image directory.
  -> FilePath                     -- ^ Name of image directory where images will be stored
  -> ShrinkSize                   -- ^ Denominator for all dimensions. Useful for displaying high DPI images in small sizes, for retina displays. Otherwise set to 1.
  -> EnvironmentOptions           -- ^ System environment settings
  -> (MathType -> FormulaOptions) -- ^ LaTeX environment settings for each equation type (display and inline)
  -> Pandoc -> IO Pandoc
convertAllFormulaeFiles x y a b c = walkM $ convertFormulaFiles x y a b c
