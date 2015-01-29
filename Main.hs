{-# LANGUAGE OverloadedStrings, ScopedTypeVariables#-}
module Main where
import Data.Monoid
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text.Encoding as T (decodeUtf8)
import Data.List (intersperse)
import qualified Data.List 
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Maybe (catMaybes)
import Control.Applicative
import Control.Monad (when)
import Data.Attoparsec.Text 
import System.Environment (getArgs)
import qualified Options.Applicative as O

data Options = Options {  
      template :: Template
    , values :: [Text]
    } deriving Show

data Template = TemplateFile FilePath | TemplateText Text deriving (Show)

parseOpts :: O.Parser Options
parseOpts = Options 
    <$> (tmplText <|> tmplFile)
    <*> tmplValues

tmplValues :: O.Parser [Text]
tmplValues = (many (T.pack <$> O.strArgument (O.metavar "VALUE")))

tmplText = TemplateText . T.pack 
      <$> O.strOption (O.short 't' <> O.metavar "TEMPLATE" <> O.help "Template string")

tmplFile = TemplateFile 
      <$> O.strOption (O.metavar "FILE" <> O.short 'f' <> O.help "Template file")

opts = O.info (O.helper <*> parseOpts)
          (O.fullDesc 
          <> O.progDesc "Inject args and STDIN into a SQL template string" 
          <> O.header "sqltmpl")

main = do
  Options tmpl values <- O.execParser opts
  template <- case tmpl of
                  TemplateFile fp -> T.readFile fp
                  TemplateText t -> return t
  let chunks :: [TemplateChunk] 
      chunks = parseText template
  values' <- if StdinPlaceholder `elem` chunks 
             then do
                  input <- T.getContents
                  return $ values ++ [input]
             else return values
  let result = evalText chunks values'
  T.putStrLn result


data ValType = String | Bool | Number deriving (Eq, Show)

data TemplateChunk = 
      PassthroughText Text 
    | Placeholder Int ValType 
    | StdinPlaceholder 
    deriving (Show, Eq)

evalText :: [TemplateChunk] -> [Text] -> Text
evalText xs vals = mconcat $ map (evalChunk vals) xs

evalChunk :: [Text] -> TemplateChunk -> Text
evalChunk vs (PassthroughText s) = s
-- if there is a stdin placeholder, the value for it will be at the
-- end of the list
evalChunk vs StdinPlaceholder = wrapQuote (last vs)
evalChunk vs (Placeholder idx _) | (vs !! idx) == "null" = "NULL"
evalChunk vs (Placeholder idx String) = wrapQuote (vs !! idx)
evalChunk vs (Placeholder idx Number) = (vs !! idx)
evalChunk vs (Placeholder idx Bool) | (vs !! idx) == "t" = "true"
evalChunk vs (Placeholder idx Bool) | (vs !! idx) == "f" = "false"

wrapQuote x = T.singleton '\'' <> (escapeText x) <> T.singleton '\''

escapeText = T.pack . escapeStringLiteral . T.unpack 

escapeStringLiteral :: String -> String
escapeStringLiteral ('\'':xs) = '\'': ('\'' : escapeStringLiteral xs)
escapeStringLiteral (x:xs) = x : escapeStringLiteral xs
escapeStringLiteral [] = []

parseText :: Text -> [TemplateChunk]
parseText = either error id . parseOnly (many textChunk)

textChunk = placeholderChunk <|> passChunk

placeholderChunk :: Parser TemplateChunk
placeholderChunk = do
    try (char '$')
    argPlaceholder <|> stdinPlaceholder

argPlaceholder :: Parser TemplateChunk
argPlaceholder = do 
    idx <- decimal
    type' <- pType
    return $ Placeholder (idx - 1) type'

stdinPlaceholder :: Parser TemplateChunk
stdinPlaceholder = do 
    string "STDIN" 
    return StdinPlaceholder

pType :: Parser ValType
pType = 
  (do
    try (char ':') 
    (Bool <$ string "bool") <|> (Number <$ string "num"))
  <|> pure String
  
passChunk :: Parser TemplateChunk
passChunk = PassthroughText <$> takeWhile1 (notInClass "$")


------------------------------------------------------------------------

