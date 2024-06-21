PoC Skip move contracts
=============

This repository has PoC of contracts to connect with Skip API. Basic code structure is similar with [Skip CosmWasm contracts](https://github.com/skip-mev/skip-api-contracts).
The contracts are available to

1. swap_and_action in one transaction.
2. interacting with Initia standard dex module. It can swap using swap_exact_asset_in and swap_exact_asset_out.
3. querying swap simulations and spot price.
4. three actions after swapping assets: transfer, IBC transfer, contract call.
5. executing `swap_exact_action` from IBC transfer message of another chain.

Entry point contract
-------------

Dynamic dispatch is not allowed in move contract, so we utilize cosmos message interface to execute other move contract with module address and name like SubMsg of CosmWasm (you can get idea how it works in the following codes, <https://github.com/initia-labs/initia/blob/main/x/move/keeper/handler.go#L271>).

This contract acts like as follows.

### Initiate module

When deploying the module, it saves a default swap-adaptor address which connects with Initia standard library dex module, <https://github.com/initia-labs/initiavm/blob/main/precompile/modules/initia_stdlib/sources/dex.move>. You can append other adaptors dynamically after.

### Swap and action

It makes a swap message first which interacts with a swap-adaptor module. To interact with another module, you should specify `module_address`, `module_name`, `function_name`, `args` correctly. You can make swap message arguments easily in `create_swapmsg_args` function.

```move
fun create_swapmsg_args(
 user_swap_amount: u64,
 pools: vector<Object<Metadata>>,
 coins: vector<Object<Metadata>>,
 min_amount: u64,
): vector<vector<u8>> {
 let msg_args = vector<vector<u8>>[];
 let amount_arg = bcs::to_bytes(&user_swap_amount);
 let pools_arg = bcs::to_bytes(&pools);
 let coins_arg = bcs::to_bytes(&coins);
 let min_amount_arg = bcs::to_bytes(&min_amount);

 vector::push_back(&mut msg_args, amount_arg);
 vector::push_back(&mut msg_args, pools_arg);
 vector::push_back(&mut msg_args, coins_arg);
 vector::push_back(&mut msg_args, min_amount_arg);

 msg_args
}
```

After making a swap message, it makes `post_action` message from `create_postaction_args`.

```move
fun create_postaction_args(
 coin: Object<Metadata>,
 pre_swap_balance: u64,
 timeout_timestamp: u64,
 post_swap_action: u8,
 action_args: vector<vector<u8>>,
): vector<vector<u8>> {
 let msg_args = vector<vector<u8>>[];
 let coin_arg = bcs::to_bytes(&coin);
 let amount_arg = bcs::to_bytes(&amount);
 let timeout_timestamp_arg = bcs::to_bytes(&timeout_timestamp);
 let post_swap_action_arg = bcs::to_bytes(&post_swap_action);
 let action_arg = bcs::to_bytes(&action_args);

 vector::push_back(&mut msg_args, coin_arg);
 vector::push_back(&mut msg_args, amount_arg);
 vector::push_back(&mut msg_args, timeout_timestamp_arg);
 vector::push_back(&mut msg_args, post_swap_action_arg);
 vector::push_back(&mut msg_args, action_arg);

 msg_args
}
```

This `post_action` message calls `post_action` function. This function unpacks `action_arg` according to each action to make each message. `action_arg` is Base64-encoded after BCS-encoded. To pack `action_arg`, you can refer helper functions `pack_action_transfer_args`, `pack_action_ibctransfer_args` and `pack_action_contract_args`.

Swap adaptor contract
-------------

`initiadex` module is a swap adaptor which connects with Initia standard library DEX module(initia_std::dex) which is based on [Balancer](https://balancer.fi/whitepaper.pdf). This contract provides two swap functions: `swap_exact_asset_in`, `swap_exact_asset_out`. You are also able to query simulation results through `simulate_swap_exact_asset_in`, `simulate_swap_exact_asset_out` and `spot_price` with `get_spot_price`. Note that a `signer` of the functions should be an owner of provided coin. You can check how provided coin works on swap function in Initia DEX module.

```move
public entry fun swap_script(
 account: &signer,
 pair: Object<Config>,
 offer_coin: Object<Metadata>,
 offer_coin_amount: u64,
 min_return: Option<u64>,
) acquires Config, Pool {
 let offer_coin = coin::withdraw(account, offer_coin, offer_coin_amount);
 let return_coin = swap(pair, offer_coin);

 assert!(
  option::is_none(&min_return) || *option::borrow(&min_return) <= fungible_asset::amount(&return_coin),
  error::invalid_state(EMIN_RETURN),
 );

 coin::deposit(signer::address_of(account), return_coin);
}
```

In these contracts, all coins are always owned by a message sender before transfering to another account.

How to make IBC message
-------------

When you call the entry point contract with IBC transfer from another chain, you should provide memo exactly following [Initia IBC-hooks](https://github.com/initia-labs/initia/tree/main/x/move/ibc-middleware). To provide `swap_and_action` args as base64 encoded bytes array, you can refer the helper function, `pack_swap_and_action_args`.

```move
fun pack_swap_and_action_args(
 swap_venue_name: String,
 swap_function_name: String,
 user_swap_coin: address,
 user_swap_amount: u64,
 pools: vector<address>,
 coins: vector<address>,
 min_swap_coin: address,
 min_swap_amount: u64,
 timeout_timestamp: u64,
 post_swap_action: u8,
 action_args: vector<vector<u8>>
): vector<String> {
 let args = vector<String>[];
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&swap_venue_name)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&swap_function_name)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&user_swap_coin)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&user_swap_amount)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&pools)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&coins)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&min_swap_coin)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&min_swap_amount)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&timeout_timestamp)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&post_swap_action)));
 vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&action_args)));
 
 args
}
```

Ack callback
-------------

Before you send a IBC transfer message, you should store a specific callback id into your ack-callback contract. Initia ack hook calls functions `ibc_ack` or `ibc_timeout` with the callback id. You can refer `@skip::ackcallback` module which simply sends token to `@skip` address when receiving an ack.

Example instructions
-------------

Swap and action

```bash
POST_SWAP_ACTION = 
 0: POST_ACTION_TRANSFER
 1: POST_ACTION_IBCTRANSFER
 2: POST_ACTION_CONTRACT
 3: POST_ACTION_OPBRIDGE

RAW_HEX_BYTES_ARGS = pack_action_{action}_args(...)
ibc transfer ex) 43574e6f595735755a5777744d413d3d,4b6a42344d555245526a4646516b4935517a49334f5459334e5452465154464551555243524556464f544579515549334f544e44526a59304e773d3d,41414141414141414141413d,32424941414141414141413d,41413d3d

$ initiad tx move execute ${SKIP_MODULE_ADDRESS} entrypoint swap_and_action --args "string:initiadex string:swap_exact_asset_in address:${USER_SWAP_COIN_METADATA} u64:${USER_SWAP_COIN_AMOUNT} vector<address>:${PAIR_METADATA} vector<address>:${COIN_1_METADATA},${COIN_2_METADATA} address:${MIN_SWAP_COIN_METADATA} u64:${MIN_SWAP_COIN_AMOUNT} u64:${TIMEOUT_TIMESTAMP} u8:${POST_SWAP_ACTION} vector<raw_hex>:${RAW_HEX_BYTES_ARGS}" --from=node0 --gas=auto --gas-adjustment 1.5 --gas-prices 0.15uinit --chain-id=localnet
```

Query

```bash
initiad query move view ${SKIP_MODULE_ADDRESS} initiadex simulate_swap_exact_asset_in --args "u64:${SWAP_AMOUNT} vector<address>:${PAIR_METADATA} vector<address>:${COIN_1_METADATA},${COIN_2_METADATA}"
```

IBC transfer with hermes

```bash
BASE64_ENCODED_BYTES_ARRAY = pack_swap_and_action_args(...)
ex) \"CWluaXRpYWRleA==\",\"E3N3YXBfZXhhY3RfYXNzZXRfaW4=\",\"h5IaK1CkAxVs+K+tdo/W394muRPi7kYLEBXl9+8XVdA=\",\"ECcAAAAAAAA=\",\"ASqe+Vd8X7NtKZHZ+6nLZe2Ls/SbFxkCGtMtzxwYZxTd\",\"AoeSGitQpAMVbPivrXaP1t/eJrkT4u5GCxAV5ffvF1XQjkczvavPfUr8PRTw3UbJv1L7D86eS5lsk54ZW4vIkdk=\",\"jkczvavPfUr8PRTw3UbJv1L7D86eS5lsk54ZW4vIkdk=\",\"ZAAAAAAAAAA=\",\"wNHzDUbCsBc=\",\"AA==\",\"ASxBQUFBQUFBQUFBQUFBQUFBMjVMbVMxeFJxTzNLRXdOTlFTZ0dJZ3NBWStFPQ==\"

$ hermes tx ft-transfer --denom=uinit --memo="{\"move\":{\"module_address\":\"${SKIP_MODULE_ADDRESS}\",\"module_name\":\"entrypoint\",\"function_name\":\"swap_and_action\",\"type_args\":[],\"args\":[${BASE64_ENCODED_BYTES_ARRAY}]}}" --amount=10000 --dst-chain=localnet --src-chain=localnet1 --src-channel=channel-0 --src-port=transfer --timeout-height-offset=100 --timeout-seconds=600 --receiver="${SKIP_MODULE_ADDRESS}::entrypoint::swap_and_action"
```

References
-------------

* Move book: <https://aptos.dev/move/book/summary/>
* Object model: <https://aptos.dev/standards/aptos-object/>
* Initia standard library: <https://github.com/initia-labs/initiavm/blob/main/precompile/modules/initia_stdlib/>
* Build and publish contracts instructions: <https://app.gitbook.com/o/VC1Rsak51RJaeaQhM2YE/s/pUvrGia2zAh06hjawOb6/initia-developer-tutorials/6.-build-and-publish-contracts/move-module>
* Interacting with Initia CLI: <https://app.gitbook.com/o/VC1Rsak51RJaeaQhM2YE/s/pUvrGia2zAh06hjawOb6/developers/virtual-machines/movevm/interact-with-cli>
