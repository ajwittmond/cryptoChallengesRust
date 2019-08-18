{-# LANGUAGE BinaryLiterals #-} 
-- | Byte manipulation utilities.  This module assumes little endianness.
module BinUtils
(hexToBytes,
 base64ToBytes,
 toBase64,
 toHex,
 blockXor

  )
where

import qualified Data.ByteString as B
import Data.String
import Data.Word
import Data.Bits
import Data.List
import qualified Data.Text as T
import Control.Arrow
import Data.List.Split
import qualified Data.Map.Strict as M
import Data.Tuple
import Data.Bool
import Debug.Trace

data Encoding = Enc Word32 (M.Map Int Char) (M.Map Char Int)

encodingFromList :: [(Int,Char)] -> Encoding
encodingFromList lst = Enc (fromIntegral $ length lst) (M.fromList lst) (M.fromList $ map swap lst)

hex = encodingFromList $ zip [0..15] (['0'..'9']++['a'..'f'])
base64 = encodingFromList $ zip [0..63] (['A'..'Z']++['a'..'z']++['0'..'9']++"+/")

-- unsafe
charToInt :: (Integral a) => Encoding -> Char -> a
charToInt (Enc l to from) c = fromIntegral $ from M.! c

--works by shifting so out of range bytes will be zero
getByte :: (Integral a,Bits a) => a -> Int -> Word8
getByte a i = fromIntegral $ shiftL a (i*8)

-- | convert a FiniteBits type to a list type.
toBytes :: (Integral a,FiniteBits a) => a -> [Word8]
toBytes a = map (getByte a) [0..(finiteBitSize a `div` 8) - 1]

fromBytes :: (Integral a, Bits a) => [Word8] -> a
fromBytes ws = foldl' (.|.) 0 $ map (uncurry shiftL . first fromIntegral) $ zip (reverse ws) [0,8..]

getBits :: Word32 -> Int
getBits l = ( sum $ map (bool 0 1 .(>0). shiftR l) [0..32] ) - 1
--assumes data type can be broken into bytes.  May add trailing zeroes if sizes do not line up.
encodeBits :: (Integral a,FiniteBits a, Show a) => Encoding -> a -> [Char]
encodeBits (Enc l to _) a =
  let bits = getBits l
  in  map (\b -> (to M.!) $ fromIntegral $ (flip shiftR (finiteBitSize a - bits)) $ shiftL a b)
          [0,bits..bits * (ceiling (fromIntegral (finiteBitSize a) / fromIntegral bits :: Double) - 1)]

--unsafe: does not check if all the data passed fits in the bits asked for
decodeBits :: (Show a,Integral a, Bits a) => Encoding -> [Char] -> a
decodeBits (Enc l _ from) s =
  let bits = getBits l
  in foldl (.|.) 0 $ map (uncurry shiftL . first (fromIntegral . ( from M.! ))) $
                     zip (reverse s) [0,bits..]

-- | Convert a hex string to bytes
hexToBytes :: String -> B.ByteString
hexToBytes s = B.pack $
  concatMap (\ls -> toBytes  $ ( decodeBits hex ls :: Word8)) (chunksOf 2 s)

-- | Convert a base64 string to bytes filling in zeroes if the number of characters
--   is not a multiple of three
base64ToBytes :: String -> B.ByteString
base64ToBytes s = B.pack $
  concatMap (\ls -> toBytes
                     ( decodeBits base64 ls :: Word16 )
            ) (chunksOf 3 $ filter (/= '=') s)

-- | Converts a byte string to Base64 potentially adding trailing zeroes
toBase64 :: B.ByteString -> String
toBase64 b =
  let  size = ceiling $  fromIntegral ( B.length b ) * 4 / 3
       ls = take size $ concatMap (\w -> take 4 $ encodeBits base64 w)
              (map (fromBytes . (take 4) .(++ repeat 0)) $ chunksOf 3 $ B.unpack b :: [Word32])
  in ls ++ take (if (size `mod` 4) /= 0 then 4 - (size `mod` 4) else 0) (repeat '=')

-- | Convert a byte string to hex potentially adding trailing zeroes
toHex :: B.ByteString -> String
toHex b = concatMap (\byte -> encodeBits hex byte)
                    (B.unpack b)

-- | xors the second string with the first one repeated to match the length of the second one
blockXor :: B.ByteString -> B.ByteString -> B.ByteString
blockXor block s = B.pack $ map (uncurry xor) $ zip (cycle $ B.unpack block) (B.unpack s)