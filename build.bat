@echo off
setlocal enabledelayedexpansion

odin.exe build src -target:orca_wasm32 -out:module.wasm 

IF %ERRORLEVEL% NEQ 0 (
	echo ERROR
	EXIT /B %ERRORLEVEL%
)

orca bundle --name output --resource-dir data module.wasm