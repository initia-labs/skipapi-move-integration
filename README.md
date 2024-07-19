Skip move contracts
=============

The contracts are available to

1. swap_and_action in one transaction.
2. interacting with Initia dex, stableswap, minitswap modules. It can swap using swap_exact_asset_in and swap_exact_asset_out.
3. querying swap simulations and spot price.
4. four actions after swapping assets: transfer, IBC transfer, contract call, OP bridge.

Entry point contract
-------------
## Swap and action
You can enter data according to the arguments of the function `swap_and_action` below
```move
public entry fun swap_and_action(
    account: &signer,
    venues: vector<u8>,
    function: u8,
    // this is used as max_offer_amount in swap_exact_asset_out
    amount_in: u64, 
    // this is used as min_amount in swap_exact_asset_in
    amount_out: u64, 
    pools: vector<vector<String>>,
    coins: vector<vector<String>>,

    post_action: u8,
    timeout_timestamp: u64,
    recover_address: String,
    post_action_args: vector<vector<u8>>,
)
```
Possible values for venue are:
```move
const INITIA_DEX: u8 = 0;
const INITIA_STABLESWAP: u8 = 1;
const INITIA_MINITSWAP: u8 = 2;
```
for function: 
```move
const SWAP_FUNCTION_SWAP_EXACT_ASSET_IN: u8 = 0;
const SWAP_FUNCTION_SWAP_EXACT_ASSET_OUT: u8 = 1;
```

for post_action:
```move
const POST_ACTION_TRANSFER: u8 = 0;
const POST_ACTION_IBCTRANSFER: u8 = 1;
const POST_ACTION_CONTRACT: u8 = 2;
const POST_ACTION_OPBRIDGE: u8 = 3;
```

### Swap

#### swap_exact_asset_in
When swapping with swap_exact_amount_in, `amount_in` acts as `swap_amount` and `amount_out` acts as `min_amount`.

#### swap_exact_asset_out
When swapping with swap_exact_amount_out, `amount_in` acts as `max_offer_amount` and `amount_out` acts as `swap_amount`.

### Post action
For post action arguments, you can query one of view functions to encode as bcs.

```bash
$ initiad q move view_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point pack_action_opbridge_args --args='"1" "init1g35jgwqehh3sm49c92fmzw3fdyj3qzzqhfl5va" ""' --node=https://rpc.initiation-1.initia.xyz

data: '["0100000000000000","2b696e6974316733356a67777165686833736d3439633932666d7a77336664796a33717a7a7168666c357661","00"]'
events: []
gas_used: "315"
```

```move
#[view]
fun pack_action_transfer_args(to_address: String): vector<vector<u8>>{
    let action_args = vector<vector<u8>>[];
    vector::push_back(&mut action_args, bcs::to_bytes(&to_address));
    action_args
}

// @dev: receiver is cosmos address
#[view]
fun pack_action_ibctransfer_args(source_channel: String, receiver: String, memo: String): vector<vector<u8>> {
    let action_args = vector<vector<u8>>[];
    vector::push_back(&mut action_args, bcs::to_bytes(&source_channel));
    vector::push_back(&mut action_args, bcs::to_bytes(&receiver));
    vector::push_back(&mut action_args, bcs::to_bytes(&memo));
    action_args
}

#[view]
fun pack_action_contract_args(module_address: address, module_name: String, function_name: String, type_args: vector<String>, args: vector<vector<u8>>): vector<vector<u8>> {
    let action_args = vector<vector<u8>>[];
    vector::push_back(&mut action_args, bcs::to_bytes(&module_address));
    vector::push_back(&mut action_args, bcs::to_bytes(&module_name));
    vector::push_back(&mut action_args, bcs::to_bytes(&function_name));
    vector::push_back(&mut action_args, bcs::to_bytes(&type_args));
    vector::push_back(&mut action_args, bcs::to_bytes(&args));
    action_args
}

#[view]
fun pack_action_opbridge_args(bridge_id: u64, to: String, data: String): vector<vector<u8>> {
    let action_args = vector<vector<u8>>[];
    vector::push_back(&mut action_args, bcs::to_bytes(&bridge_id));
    vector::push_back(&mut action_args, bcs::to_bytes(&to));
    vector::push_back(&mut action_args, bcs::to_bytes(&data));
    action_args
}
```

## Examples
- Swap_exact_asset_in `ueth`, `uinit`, `uusdc` in order from `initia_dex`
- IBC transfer to `init1g35jgwqehh3sm49c92fmzw3fdyj3qzzqhfl5va` on `birdee-1` chain as post action
- Set `init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp` as recover_address
```bash
initiad tx move execute_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point swap_and_action --args='[0] 0 "1000" "10" [["move/a2b0d3c8e53e379ede31f3a361ff02716d50ec53c6b65b8c48a81d5b06548200","move/dbf06c48af3984ec6d9ae8a9aa7dbb0bb1e784aa9b8c4a5681af660cf8558d7d"]] [["ueth","uinit","uusdc"]] 1 "1821364848632000000" "init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp" ["0a6368616e6e656c2d3235","2b696e6974316733356a67777165686833736d3439633932666d7a77336664796a33717a7a7168666c357661","00"]'
```

- Swap_exact_asset_out `ueth`, `uinit`, `uusdc` in order from `initia_dex`
- OP bridge transfer to `init1g35jgwqehh3sm49c92fmzw3fdyj3qzzqhfl5va` on `minimove-1` chain as post action
- Set `init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp` as recover_address
```bash
initiad tx move execute_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point swap_and_action --args='[0] 1 "10000" "6200000" [["move/a2b0d3c8e53e379ede31f3a361ff02716d50ec53c6b65b8c48a81d5b06548200","move/dbf06c48af3984ec6d9ae8a9aa7dbb0bb1e784aa9b8c4a5681af660cf8558d7d"]] [["ueth","uinit","uusdc"]] 3 "1821364848632000000" "init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp" ["0a6368616e6e656c2d3235","2b696e6974316733356a67777165686833736d3439633932666d7a77336664796a33717a7a7168666c357661","00"]'
```

- Query `spot_price` `ueth`, `uinit`, `uusdc` in order from `initia_dex`
```bash
initiad q move view_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point get_spot_price --args='[0] [["move/a2b0d3c8e53e379ede31f3a361ff02716d50ec53c6b65b8c48a81d5b06548200","move/dbf06c48af3984ec6d9ae8a9aa7dbb0bb1e784aa9b8c4a5681af660cf8558d7d"]] [["ueth","uinit","uusdc"]]'
```

- Query `simulate_swap_exact_asset_in` `uusdc`, `uinit` in order from `initia_dex`
```bash
initiad q move view_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point simulate_swap_exact_asset_in --args='"10000" [0] [["move/dbf06c48af3984ec6d9ae8a9aa7dbb0bb1e784aa9b8c4a5681af660cf8558d7d"]] [["uusdc","uinit"]]'
```

- Query `simulate_swap_exact_asset_out` `uusdc`, `uinit` in order from `initia_dex`
```bash
initiad q move view_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point simulate_swap_exact_asset_out --args='"10000" [0] [["move/dbf06c48af3984ec6d9ae8a9aa7dbb0bb1e784aa9b8c4a5681af660cf8558d7d"]] [["uusdc","uinit"]]'
```

- Query `simulate_swap_exact_asset_in_metadata` `ueth`, `uinit`, `uusdc` in order from `initia_dex`
```bash 
initiad q move view_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point simulate_swap_exact_asset_in_with_metadata --args='"1000" [0] [["move/a2b0d3c8e53e379ede31f3a361ff02716d50ec53c6b65b8c48a81d5b06548200","move/dbf06c48af3984ec6d9ae8a9aa7dbb0bb1e784aa9b8c4a5681af660cf8558d7d"]] [["ueth","uinit","uusdc"]] true'
```

- Query `simulate_swap_exact_asset_out_metadata` `ueth`, `uinit`, `uusdc` in order from `initia_dex`
```bash 
initiad q move view_json 0x777105889E6E42F2BED14DD4D7286C9E982A3E31 entry_point simulate_swap_exact_asset_out_with_metadata --args='"1000" [0] [["move/a2b0d3c8e53e379ede31f3a361ff02716d50ec53c6b65b8c48a81d5b06548200","move/dbf06c48af3984ec6d9ae8a9aa7dbb0bb1e784aa9b8c4a5681af660cf8558d7d"]] [["ueth","uinit","uusdc"]] false'
```