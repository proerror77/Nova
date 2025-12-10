use crypto_core::{decrypt, encrypt, generate_nonce, generate_x25519_keypair};

#[test]
fn roundtrip_echo_stub() {
    // Generate proper X25519 keypairs (32 bytes each)
    let (sender_pub, sender_sec) = generate_x25519_keypair().expect("generate sender keypair");
    let (recipient_pub, recipient_sec) = generate_x25519_keypair().expect("generate recipient keypair");
    
    let msg = b"hello";
    let nonce = generate_nonce();
    
    // Encrypt: sender uses recipient's public key and their own secret key
    let ct = encrypt(msg, &recipient_pub, &sender_sec, &nonce).expect("encrypt");
    
    // Decrypt: recipient uses sender's public key and their own secret key
    let pt = decrypt(&ct, &sender_pub, &recipient_sec, &nonce).expect("decrypt");
    assert_eq!(pt, msg);
}

#[test]
fn nonce_randomness_length() {
    let n1 = generate_nonce();
    let n2 = generate_nonce();
    assert_eq!(n1.len(), 24);
    assert_ne!(n1, n2, "nonce should be random");
}
