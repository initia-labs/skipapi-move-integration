module skip::ackcallback {	
    use initia_std::simple_map::{Self, SimpleMap};
    use initia_std::coin;
    use initia_std::object::{Object};
    use initia_std::fungible_asset::{Metadata};
    use initia_std::event;

    struct ModuleStore has key {
        current_id: u64,
        acks: SimpleMap<u64, RecoverInfo>,
    }

    struct RecoverInfo has key, store, drop {
        recover_address: address,
        coin_amount: u64,
        coin_metadata: Object<Metadata>,
    }

    #[event]
    struct StoreRecoverAddress has drop, store {
        callback_id: u64,
        recover_address: address,
        coin_metadata: Object<Metadata>,
    }

    #[event]
    struct AckCallback has drop, store {
        callback_id: u64,
        is_success: bool,
        recover_address: address,
        coin_metadata: Object<Metadata>,
        moved_amount: u64,
    }

    #[event]
    struct TimeoutCallback has drop, store {
        callback_id: u64,
        recover_address: address,
        coin_metadata: Object<Metadata>,
        moved_amount: u64,
    }

    fun init_module(chain: &signer) {
        let acks = simple_map::create<u64, RecoverInfo>();
        move_to(chain, ModuleStore {
            current_id: 0,
            acks,
        });
    }

    public fun store_recover_address(
        recover_address: address,
        coin_amount: u64,
        coin_metadata: Object<Metadata>,
    ): u64 acquires ModuleStore{
        let module_store = borrow_global_mut<ModuleStore>(@skip);
        let recover_info = RecoverInfo{
            recover_address,
            coin_amount,
            coin_metadata,
        };

        simple_map::add(&mut module_store.acks, module_store.current_id, recover_info);
        module_store.current_id = module_store.current_id + 1;

        event::emit<StoreRecoverAddress>(
			StoreRecoverAddress {
                callback_id: module_store.current_id - 1,
				recover_address: recover_address,
                coin_metadata: coin_metadata,
			}
		);

        module_store.current_id - 1 
    }

    public entry fun ibc_ack(
        account: &signer,
        callback_id: u64,
        is_success: bool,
    ) acquires ModuleStore {
        let module_store = borrow_global_mut<ModuleStore>(@skip);
        let (_, recover_info) = simple_map::remove(&mut module_store.acks, &callback_id);

        if(!is_success) {
            coin::transfer(account, recover_info.recover_address, recover_info.coin_metadata, recover_info.coin_amount);
        };
        event::emit<AckCallback>(
			AckCallback {
                callback_id,
                is_success,
				recover_address: recover_info.recover_address,
                coin_metadata: recover_info.coin_metadata,
                moved_amount: recover_info.coin_amount,
			}
		);
    }

    public entry fun ibc_timeout(
        account: &signer,
        callback_id: u64,
    ) acquires ModuleStore {
        let module_store = borrow_global_mut<ModuleStore>(@skip);
        let (_, recover_info) = simple_map::remove(&mut module_store.acks, &callback_id);

        coin::transfer(account, recover_info.recover_address, recover_info.coin_metadata, recover_info.coin_amount);
        event::emit<TimeoutCallback>(
			TimeoutCallback {
                callback_id,
				recover_address: recover_info.recover_address,
                coin_metadata: recover_info.coin_metadata,
                moved_amount: recover_info.coin_amount,
			}
		);
    }
}