#! /bin/sh

function assertEnvironment {
	if [ -z $1 ]; then 
		echo $2
		exit 127
	fi
}

assertEnvironment "${SRCROOT}" "Please set SRCROOT to project root folder"

unset SDKROOT

swift run -c release --package-path BuildTools swiftformat "${SRCROOT}" \
--enable andOperator,\
anyObjectProtocol,\
blankLinesAroundMark,\
blankLinesAtEndOfScope,\
blankLinesAtStartOfScope,\
blankLinesBetweenScopes,\
consecutiveBlankLines,\
consecutiveSpaces,\
duplicateImports,\
elseOnSameLine,\
emptyBraces,\
enumNamespaces,\
fileHeader,\
hoistPatternLet,\
indent,\
isEmpty,\
leadingDelimiters,\
linebreakAtEndOfFile,\
linebreaks,\
modifierOrder,\
numberFormatting,\
preferKeyPath,\
redundantBackticks,\
redundantBreak,\
redundantExtensionACL,\
redundantFileprivate,\
redundantGet,\
redundantLet,\
redundantLetError,\
redundantNilInit,\
redundantObjc,\
redundantParens,\
redundantPattern,\
redundantRawValues,\
redundantReturn,\
redundantSelf,\
redundantType,\
redundantVoidReturnType,\
semicolons,\
sortedImports,\
sortedSwitchCases,\
spaceAroundBraces,\
spaceAroundBrackets,\
spaceAroundComments,\
spaceAroundGenerics,\
spaceAroundOperators,\
spaceAroundParens,\
spaceInsideBraces,\
spaceInsideBrackets,\
spaceInsideComments,\
spaceInsideGenerics,\
spaceInsideParens,\
strongOutlets,\
strongifiedSelf,\
todos,\
trailingCommas,\
trailingSpace,\
typeSugar,\
unusedArguments,\
void,\
wrap,\
wrapArguments,\
wrapAttributes,\
wrapEnumCases,\
wrapMultilineStatementBraces,\
wrapSwitchCases \
--disable braces,\
redundantInit,\
trailingClosures \
--commas inline \
--exponentcase uppercase \
--header strip \
--hexliteralcase uppercase \
--ifdef indent \
--indent 4 \
--self remove \
--semicolons never \
--swiftversion 5.2 \
--trimwhitespace always \
--maxwidth 130 \
--wraparguments before-first \
--funcattributes same-line \
--typeattributes same-line \
--varattributes same-line \
--wrapcollections before-first \
--exclude Pods, Generated, \
  R.generated.swift, \
  fastlane/swift, \
  Dependencies,  \
  LoopKit,  \
  LibreTransmitter, \
  G7SensorKit, \
  OmniKit,  \
  dexcom-share-client-swift, \
  CGMBLEKit, \
  RileyLinkKit, \
  OmniBLE, \
  MinimedKit, \
  TidepoolService \
  DanaKit 
