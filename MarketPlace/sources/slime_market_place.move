module slime_marketplace::slime_nft_market_place {
    use std::error;
    use std::signer;
    use std::option::{Self, Option};
    use aptos_std::smart_vector;
    use aptos_std::smart_vector::SmartVector;

    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::object::{Self, DeleteRef, ExtendRef, Object, ObjectCore};

    const APP_OBJECT_SEED: vector<u8> = b"MARKETPLACE";

    /// There exists no listing.
    const ENO_LISTING: u64 = 1;
    /// There exists no seller.
    const ENO_SELLER: u64 = 2;

    const ENOT_AUTHORIZED: u64 = 3;

    // Core data structures

    struct MarketplaceSigner has key {
        extend_ref: ExtendRef,
    }

    struct MarketplaceAdmin has key {
        fee_recipient: address,
        price_fee: u64,
    }


    struct Sellers has key {
        /// All addresses of sellers.
        addresses: SmartVector<address>
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Listing has key {
        /// The item owned by this listing, transferred to the new owner at the end.
        object: Object<ObjectCore>,
        /// The seller of the object.
        seller: address,
        /// Used to clean-up at the end.
        delete_ref: DeleteRef,
        /// Used to create a signer to transfer the listed item, ideally the TransferRef would support this.
        extend_ref: ExtendRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct FixedPriceListing<phantom CoinType> has key {
        /// The price to purchase the item up for listing.
        price: u64,
    }

    struct SellerListings has key {
        /// All object addresses of listings the user has created.
        listings: SmartVector<address>
    }

    // Functions

    // This function is only called once when the module is published for the first time.
    fun init_module(deployer: &signer) {
        let constructor_ref = object::create_named_object(
            deployer,
            APP_OBJECT_SEED,
        );
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let marketplace_signer = &object::generate_signer(&constructor_ref);

        move_to(marketplace_signer, MarketplaceSigner {
            extend_ref,
        });
    }

    public fun get_marketplace_signer_addr(): address {
        object::create_object_address(&@slime_marketplace, APP_OBJECT_SEED)
    }

    public fun get_marketplace_signer(_arg0: address) : signer  {
        abort 0
    }
    
    fun get_marketplace_signer_v2(marketplace_signer_addr: address): signer acquires MarketplaceSigner {
        object::generate_signer_for_extending(&borrow_global<MarketplaceSigner>(marketplace_signer_addr).extend_ref)
    }

    /// List an time for sale at a fixed price.
    public entry fun list_with_fixed_price<CoinType>(
        seller: &signer,
        object: Object<ObjectCore>,
        price: u64,
    ) acquires SellerListings, Sellers, MarketplaceSigner {
        list_with_fixed_price_internal<CoinType>(seller, object, price);
    }

    public(friend) fun list_with_fixed_price_internal<CoinType>(
        seller: &signer,
        object: Object<ObjectCore>,
        price: u64,        
    ): Object<Listing> acquires SellerListings, Sellers, MarketplaceSigner {
        let constructor_ref = object::create_object(signer::address_of(seller));

        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        let listing_signer = object::generate_signer(&constructor_ref);

        let listing = Listing {
            object,
            seller: signer::address_of(seller),
            delete_ref: object::generate_delete_ref(&constructor_ref),
            extend_ref: object::generate_extend_ref(&constructor_ref),
        };
        let fixed_price_listing = FixedPriceListing<CoinType> {
            price,
        };
        move_to(&listing_signer, listing);
        move_to(&listing_signer, fixed_price_listing);

        object::transfer(seller, object, signer::address_of(&listing_signer));

        let listing = object::object_from_constructor_ref(&constructor_ref);

        if (exists<SellerListings>(signer::address_of(seller))) {
            let seller_listings = borrow_global_mut<SellerListings>(signer::address_of(seller));
            smart_vector::push_back(&mut seller_listings.listings, object::object_address(&listing));
        } else {
            let seller_listings = SellerListings {
                listings: smart_vector::new(),
            };
            smart_vector::push_back(&mut seller_listings.listings, object::object_address(&listing));
            move_to(seller, seller_listings);
        };
        if (exists<Sellers>(get_marketplace_signer_addr())) {
            let sellers = borrow_global_mut<Sellers>(get_marketplace_signer_addr());
            if (!smart_vector::contains(&sellers.addresses, &signer::address_of(seller))) {
                smart_vector::push_back(&mut sellers.addresses, signer::address_of(seller));
            }
        } else {
            let sellers = Sellers {
                addresses: smart_vector::new(),
            };
            smart_vector::push_back(&mut sellers.addresses, signer::address_of(seller));
            move_to(&get_marketplace_signer_v2(get_marketplace_signer_addr()), sellers);
        };

        listing
    }

    

    public entry fun purchase<CoinType>(
        purchaser: &signer,
        object: Object<ObjectCore>,
        fee_recipient: address,
    ) acquires FixedPriceListing, Listing, SellerListings, Sellers, MarketplaceAdmin {
        let listing_addr = object::object_address(&object);
        assert!(exists<MarketplaceAdmin>(fee_recipient), ENOT_AUTHORIZED);
        let fee_recipient_address = borrow_global<MarketplaceAdmin>(fee_recipient).fee_recipient;
        let fee_price = borrow_global<MarketplaceAdmin>(fee_recipient).price_fee;
        assert!(exists<Listing>(listing_addr), error::not_found(ENO_LISTING));
        assert!(exists<FixedPriceListing<CoinType>>(listing_addr), error::not_found(ENO_LISTING));

        let FixedPriceListing {
            price,
        } = move_from<FixedPriceListing<CoinType>>(listing_addr);

        let fee = price / 100 * fee_price;
        let seller_amount = price - fee;

        let coins = coin::withdraw<CoinType>(purchaser, seller_amount);
        let fee_coins = coin::withdraw<CoinType>(purchaser, fee);

        let Listing {
            object,
            seller, 
            delete_ref,
            extend_ref,
        } = move_from<Listing>(listing_addr);

        let obj_signer = object::generate_signer_for_extending(&extend_ref);
        object::transfer(&obj_signer, object, signer::address_of(purchaser));
        object::delete(delete_ref); 

        let seller_listings = borrow_global_mut<SellerListings>(seller);
        let (exist, idx) = smart_vector::index_of(&seller_listings.listings, &listing_addr);
        assert!(exist, error::not_found(ENO_LISTING));
        smart_vector::remove(&mut seller_listings.listings, idx);

        if (smart_vector::length(&seller_listings.listings) == 0) {
            let sellers = borrow_global_mut<Sellers>(get_marketplace_signer_addr());
            let (exist, idx) = smart_vector::index_of(&sellers.addresses, &seller);
            assert!(exist, error::not_found(ENO_SELLER));
            smart_vector::remove(&mut sellers.addresses, idx);
        };

        aptos_account::deposit_coins(seller, coins);
        aptos_account::deposit_coins(fee_recipient_address, fee_coins);
    }
   
    // Helper functions
    inline fun borrow_listing(object: Object<Listing>): &Listing acquires Listing {
        let obj_addr = object::object_address(&object);
        assert!(exists<Listing>(obj_addr), error::not_found(ENO_LISTING));
        borrow_global<Listing>(obj_addr)
    }
   // unlist
    public entry fun unlist<CoinType>(
    seller: &signer,
    object: Object<ObjectCore>,
    ) acquires Listing, FixedPriceListing, SellerListings, Sellers {
        let listing_addr = object::object_address(&object);
        assert!(exists<Listing>(listing_addr), error::not_found(ENO_LISTING));
        assert!(exists<FixedPriceListing<CoinType>>(listing_addr), error::not_found(ENO_LISTING));

        let Listing {
            object,
            seller: listing_seller,
            delete_ref,
            extend_ref,
        } = move_from<Listing>(listing_addr);

        assert!(listing_seller == signer::address_of(seller), error::invalid_argument(ENO_SELLER));

        let FixedPriceListing { price: _ } = move_from<FixedPriceListing<CoinType>>(listing_addr);

        let obj_signer = object::generate_signer_for_extending(&extend_ref);
        object::transfer(&obj_signer, object, signer::address_of(seller));

        object::delete(delete_ref);

        let seller_listings = borrow_global_mut<SellerListings>(signer::address_of(seller));
        let (exist, idx) = smart_vector::index_of(&seller_listings.listings, &listing_addr);
        assert!(exist, error::not_found(ENO_LISTING));
        smart_vector::remove(&mut seller_listings.listings, idx);

        if (smart_vector::length(&seller_listings.listings) == 0) {
            let sellers = borrow_global_mut<Sellers>(get_marketplace_signer_addr());
            let (exist, idx) = smart_vector::index_of(&sellers.addresses, &signer::address_of(seller));
            assert!(exist, error::not_found(ENO_SELLER));
            smart_vector::remove(&mut sellers.addresses, idx);
        }
    }

    public entry fun set_fee_recipient(caller: &signer, new_fee_recipient: address, price_fee: u64) acquires MarketplaceAdmin {
        let caller_address = signer::address_of(caller);
        assert!(caller_address == @slime_marketplace, error::permission_denied(ENOT_AUTHORIZED));
        if (exists<MarketplaceAdmin>(@slime_marketplace)) {
            let admin_data = borrow_global_mut<MarketplaceAdmin>(@slime_marketplace);
            admin_data.fee_recipient = new_fee_recipient;
            admin_data.price_fee = price_fee;
        } else {
            move_to(caller, MarketplaceAdmin {
                fee_recipient: new_fee_recipient,
                price_fee: price_fee
            });
        }
      }

    // update price
    public entry fun update_price<CoinType>(
        seller: &signer,
        object: Object<ObjectCore>,
        new_price: u64,
        ) acquires FixedPriceListing, Listing {
            let listing_addr = object::object_address(&object);

            assert!(exists<Listing>(listing_addr), error::not_found(ENO_LISTING));
            assert!(exists<FixedPriceListing<CoinType>>(listing_addr), error::not_found(ENO_LISTING));

            let listing = borrow_global<Listing>(listing_addr);
            assert!(listing.seller == signer::address_of(seller), error::permission_denied(ENOT_AUTHORIZED));

            let fixed_price_listing = borrow_global_mut<FixedPriceListing<CoinType>>(listing_addr);
            fixed_price_listing.price = new_price;
        }
        
    // View functions

    #[view]
    public fun price<CoinType>(
        object: Object<Listing>,
    ): Option<u64> acquires FixedPriceListing {
        let listing_addr = object::object_address(&object);
        if (exists<FixedPriceListing<CoinType>>(listing_addr)) {
            let fixed_price = borrow_global<FixedPriceListing<CoinType>>(listing_addr);
            option::some(fixed_price.price)
        } else {
            // This should just be an abort but the compiler errors.
            assert!(false, error::not_found(ENO_LISTING));
            option::none()
        }
    }

    #[view]
    public fun listing(object: Object<Listing>): (Object<ObjectCore>, address) acquires Listing {
        let listing = borrow_listing(object);
        (listing.object, listing.seller)
    }

    #[view]
    public fun get_seller_listings(seller: address): vector<address> acquires SellerListings {
        if (exists<SellerListings>(seller)) {
            smart_vector::to_vector(&borrow_global<SellerListings>(seller).listings)
        } else {
            vector[]
        }
    }

    #[view]
    public fun get_sellers(): vector<address> acquires Sellers {
        if (exists<Sellers>(get_marketplace_signer_addr())) {
            smart_vector::to_vector(&borrow_global<Sellers>(get_marketplace_signer_addr()).addresses)
        } else {
            vector[]
        }
    }

}