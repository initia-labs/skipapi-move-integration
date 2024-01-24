module test_skip::simplecount {
	use std::signer;

	struct Count has key {
		count: u64
	}

	public entry fun increase(
		account: &signer
	) acquires Count{
		let account_addr = signer::address_of(account);
		if(!exists<Count>(account_addr)){
			move_to<Count>(account, Count {
				count: 1
			});
		} else {
			let count = borrow_global_mut<Count>(account_addr);
			count.count = count.count + 1;
		}
	}

	#[view]
	public fun get_count(
		account: address,
	): u64 acquires Count {
		let count = borrow_global<Count>(account);
		count.count
	}
}
