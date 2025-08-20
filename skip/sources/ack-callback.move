module skip::ack_callback {    
    use initia_std::simple_map::{Self, SimpleMap};
    use initia_std::coin;
    use initia_std::object::{Object};
    use initia_std::fungible_asset::{Metadata};
    use initia_std::event;
    use initia_std::signer;

    friend skip::entry_point;
    struct AckStore has key {
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

    public(friend) fun store_recover_address(
        account: &signer,
        recover_address: address,
        coin_amount: u64,
        coin_metadata: Object<Metadata>,
    ): u64 acquires AckStore{
        let account_address = signer::address_of(account);
        if(!exists<AckStore>(account_address)) {
            move_to<AckStore>(account, AckStore{
                current_id: 0,
                acks: simple_map::create<u64, RecoverInfo>(), 
            });
        };
        let ack_store = borrow_global_mut<AckStore>(account_address);
        let recover_info = RecoverInfo{
            recover_address,
            coin_amount,
            coin_metadata,
        };

        simple_map::add(&mut ack_store.acks, ack_store.current_id, recover_info);
        ack_store.current_id = ack_store.current_id + 1;

        event::emit<StoreRecoverAddress>(
            StoreRecoverAddress {
                callback_id: ack_store.current_id - 1,
                recover_address: recover_address,
                coin_metadata: coin_metadata,
            }
        );
        ack_store.current_id - 1 
    }

    public entry fun ibc_ack(
        account: &signer,
        callback_id: u64,
        is_success: bool,
    ) acquires AckStore {
        let recover_info = recover(account, callback_id, is_success);
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
    ) acquires AckStore {
        let recover_info = recover(account, callback_id, false);
        event::emit<TimeoutCallback>(
            TimeoutCallback {
                callback_id,
                recover_address: recover_info.recover_address,
                coin_metadata: recover_info.coin_metadata,
                moved_amount: recover_info.coin_amount,
            }
        );
    }

    public entry fun recover(
        account: &signer,
        callback_id: u64,
        is_success: bool,
    ): RecoverInfo acquires AckStore {
        let account_address = signer::address_of(account);
        let ack_store = borrow_global_mut<AckStore>(account_address);
        let (_, recover_info) = simple_map::remove(&mut ack_store.acks, &callback_id);

        if(!is_success) {
            coin::transfer(account, recover_info.recover_address, recover_info.coin_metadata, recover_info.coin_amount);
        };

        recover_info
    }
}