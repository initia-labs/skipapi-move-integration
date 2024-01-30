module skip::ackcallback {	
    use std::signer;

    use initia_std::simple_map::{Self, SimpleMap};
    use initia_std::coin;
    use initia_std::object::{Object};
    use initia_std::fungible_asset::{Metadata};

    struct ModuleStore has key {
        acks: SimpleMap<u64, Object<Metadata>>,
    }

    fun init_module(chain: &signer) {
        let acks = simple_map::create<u64,Object<Metadata>>();
        move_to(chain, ModuleStore {
            acks
        });
    }

    public entry fun store_callback_id(
        _account: &signer,
        callback_id: u64,
        coin_metadata: Object<Metadata>,
    ) acquires ModuleStore{
        let module_store = borrow_global_mut<ModuleStore>(@skip);
        if(simple_map::contains_key(&module_store.acks, &callback_id)) {
            simple_map::remove(&mut module_store.acks, &callback_id);
        };
        simple_map::add(&mut module_store.acks, callback_id, coin_metadata);
    }

    public entry fun ibc_ack(
        account: &signer,
        callback_id: u64,
        is_success: bool,
    ) acquires ModuleStore {
        let module_store = borrow_global_mut<ModuleStore>(@skip);
        let coin_sent = simple_map::borrow(&module_store.acks, &callback_id);

        if(!is_success) {
            send_balance_to_me(account, *coin_sent);
        };
        simple_map::remove(&mut module_store.acks, &callback_id);
    }

    public entry fun ibc_timeout(
        account: &signer,
        callback_id: u64,
    ) acquires ModuleStore {
        let module_store = borrow_global_mut<ModuleStore>(@skip);
        let coin_sent = simple_map::borrow(&module_store.acks, &callback_id);

        send_balance_to_me(account, *coin_sent);
        simple_map::remove(&mut module_store.acks, &callback_id);
    }

    fun send_balance_to_me(
        account: &signer,
        coin_metadata: Object<Metadata>,
    ) {
        let amount = coin::balance(signer::address_of(account), coin_metadata);
        coin::transfer(account, @skip, coin_metadata, amount);
    }
}