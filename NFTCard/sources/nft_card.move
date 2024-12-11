module aptoslime_addr::slime_nft_slime {
    use std::signer;
    use aptos_framework::event;
    use aptos_framework::object::{Self, ExtendRef, Object};
    use aptos_token_objects::collection;
    use aptos_token_objects::token::{Token, Self};
    use std::option;
    use std::signer::address_of;
    use std::string::{String, utf8};
    use aptos_std::ed25519;
    use std::vector;
    use aptos_framework::error;

    const EINVALID_SIGNATURE: u64 = 1001;
    const ENOT_AUTHORIZED: u64 = 1002;
    const EINVALID_TOKEN: u64 = 1003;

    const EAPTOSLIME_NOT_EXIST: u64 = 1;
    const APP_OBJECT_SEED: vector<u8> = b"APTOSLIME";
    const APTOSLIME_COLLECTION_NAME: vector<u8> = b"Aptoslime Collection";
    const APTOSLIME_COLLECTION_DESCRIPTION: vector<u8> = b"Aptoslime Collection Description";
    const APTOSLIME_COLLECTION_URI: vector<u8> = b"https://aptos.slimerevolution.com/static/media/iconProfile.a46ebbdf20d3cb58d3ab.png";

    struct AptoslimeParts has copy, drop, key, store {
        type: u8,
    }

    struct UsedSignatures has key, store {
        used_signatures: vector<vector<u8>>,
    }

    struct PublicKeyResource has key, store {
        public_key: vector<u8>,
    }

    struct Aptoslime has key {
        parts: AptoslimeParts,
        extend_ref: ExtendRef,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
    }

    #[event]
    struct MintAptoslimeEvent has drop, store {
        aptoslime_address: address,
        token_name: String,
    }

    struct CollectionCapability has key {
        extend_ref: ExtendRef,
    }

    fun init_module(account: &signer) {
        let constructor_ref = object::create_named_object(
            account,
            APP_OBJECT_SEED,
        );
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let app_signer = &object::generate_signer(&constructor_ref);

        move_to(app_signer, CollectionCapability {
            extend_ref,
        });

        create_aptoslime_collection(app_signer);

        move_to(account, UsedSignatures {
            used_signatures: vector::empty<vector<u8>>(),
        });
    }

    fun get_collection_address(): address {
        object::create_object_address(&@aptoslime_addr, APP_OBJECT_SEED)
    }

    fun get_collection_signer(collection_address: address): signer acquires CollectionCapability {
        object::generate_signer_for_extending(&borrow_global<CollectionCapability>(collection_address).extend_ref)
    }

    fun get_aptoslime_signer(aptoslime_address: address): signer acquires Aptoslime {
        object::generate_signer_for_extending(&borrow_global<Aptoslime>(aptoslime_address).extend_ref)
    }

    fun create_aptoslime_collection(creator: &signer) {
        let description = utf8(APTOSLIME_COLLECTION_DESCRIPTION);
        let name = utf8(APTOSLIME_COLLECTION_NAME);
        let uri = utf8(APTOSLIME_COLLECTION_URI);

        collection::create_unlimited_collection(
            creator,
            description,
            name,
            option::none(),
            uri,
        );
    }

    entry fun store_public_key(caller: &signer, public_key: vector<u8>, signature_address: address,) acquires PublicKeyResource {
        let caller_address = signer::address_of(caller);
        assert!(caller_address == @aptoslime_addr, error::permission_denied(ENOT_AUTHORIZED));
        if (exists<PublicKeyResource>(signature_address)) {
            let key_resource = borrow_global_mut<PublicKeyResource>(signature_address);
            key_resource.public_key = public_key;
        } else {
            let key_resource = PublicKeyResource { public_key };
            move_to(caller, key_resource);
        }
    }

    entry fun create_aptoslime(
        user: &signer, 
        name: String,
        type: u8,
        signed_message: vector<u8>,
        message: vector<u8>,
        uri: vector<u8>,
        signature_address: address,
    ) acquires CollectionCapability, PublicKeyResource, UsedSignatures {
        let key_resource = borrow_global<PublicKeyResource>(signature_address);

        let is_valid = verify_signature_with_fixed_key(
            key_resource.public_key,
            signed_message,
            message
        );
        assert!(is_valid, EINVALID_SIGNATURE); 

        let used_signatures = borrow_global_mut<UsedSignatures>(@aptoslime_addr);
        let already_used = vector::contains(&used_signatures.used_signatures, &signed_message);
        let uri = utf8(uri);
        let description = utf8(APTOSLIME_COLLECTION_DESCRIPTION);
        let parts = AptoslimeParts {
            type,
        };

        let collection_address = get_collection_address();
        let constructor_ref = &token::create(
            &get_collection_signer(collection_address),
            utf8(APTOSLIME_COLLECTION_NAME),
            description,
            name,
            option::none(),
            uri,
        );

        let token_signer_ref = &object::generate_signer(constructor_ref);

        let extend_ref = object::generate_extend_ref(constructor_ref);
        let mutator_ref = token::generate_mutator_ref(constructor_ref);
        let burn_ref = token::generate_burn_ref(constructor_ref);
        let transfer_ref = object::generate_transfer_ref(constructor_ref);

        // Initialize and set default Aptoslime struct values
        let aptoslime = Aptoslime {
            parts,
            extend_ref,
            mutator_ref,
            burn_ref,
        };
        move_to(token_signer_ref, aptoslime);

        // Emit event for minting Aptoslime token
        event::emit(
            MintAptoslimeEvent {
                aptoslime_address: address_of(token_signer_ref),
                token_name: name,
            },
        );

        // Transfer the Aptoslime to the user
        object::transfer_with_ref(object::generate_linear_transfer_ref(&transfer_ref), address_of(user));
    }

    public fun verify_signature_with_fixed_key(
        fixed_public_key: vector<u8>,
        signed_message: vector<u8>,
        message: vector<u8>
    ): bool {
        let public_key = ed25519::new_unvalidated_public_key_from_bytes(fixed_public_key);
        let signature = ed25519::new_signature_from_bytes(signed_message);
        let is_valid = ed25519::signature_verify_strict(&signature, &public_key, message);
        assert!(is_valid, error::invalid_argument(EINVALID_SIGNATURE));
        is_valid
    }

    #[view]
    public fun get_aptoslime_collection_name(): (String) {
        utf8(APTOSLIME_COLLECTION_NAME)
    }

    #[view]
    public fun get_aptoslime_collection_creator_address(): (address) {
        get_collection_address()
    }

    #[view]
    public fun get_aptoslime_collection_address(): (address) {
        let collection_name = utf8(APTOSLIME_COLLECTION_NAME);
        let creator_address = get_collection_address();
        collection::create_collection_address(&creator_address, &collection_name)
    }

    #[view]
    public fun get_aptoslime(aptoslime_obj: Object<Token>): (String, AptoslimeParts) acquires Aptoslime {
        let aptoslime_address = object::object_address(&aptoslime_obj);
        assert!(object::object_exists<Token>(aptoslime_address), EAPTOSLIME_NOT_EXIST);
        let aptoslime = borrow_global<Aptoslime>(aptoslime_address);
        (token::name<Token>(aptoslime_obj), aptoslime.parts)
    }

   entry fun burn_aptoslime(aptoslime_obj: Object<Token>)acquires Aptoslime {
        let aptoslime_address = object::object_address(&aptoslime_obj);
        assert!(object::object_exists<Token>(aptoslime_address), EAPTOSLIME_NOT_EXIST);
        let Aptoslime {parts, extend_ref, mutator_ref, burn_ref} = move_from<Aptoslime>(aptoslime_address);
        token::burn(burn_ref)
    }

        entry fun burn_aptoslime_v1(arg0: aptos_framework::object::Object<0x4::token::Token>,arg1: &signer) acquires Aptoslime {
        assert!(aptos_framework::object::is_owner(arg0, aptos_framework::signer::address_of(arg1)),ENOT_AUTHORIZED);
        let v0 = aptos_framework::object::object_address<0x4::token::Token>(&arg0);
        assert!(aptos_framework::object::object_exists<0x4::token::Token>(v0), 1);
        let Aptoslime {
            parts       : _,
            extend_ref  : _,
            mutator_ref : _,
            burn_ref    : v4,
        } = move_from<Aptoslime>(v0);
        0x4::token::burn(v4);
    }

}
