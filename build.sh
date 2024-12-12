odin build src -target:orca_wasm32 -out:module.wasm 
orca bundle --name output --resource-dir data module.wasm