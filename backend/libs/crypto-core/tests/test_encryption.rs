use crypto_core::{decrypt, encrypt, generate_nonce, generate_x25519_keypair};

#[test]
fn roundtrip_echo_stub() {
    let msg = b"hello";
    let nonce = generate_nonce();

    // Generate proper keypairs for sender and recipient
    let (sender_pk, sender_sk) = generate_x25519_keypair().expect("sender keypair");
    let (recipient_pk, recipient_sk) = generate_x25519_keypair().expect("recipient keypair");

    // Encrypt: sender encrypts to recipient's public key using sender's secret key
    let ct = encrypt(msg, &recipient_pk, &sender_sk, &nonce).expect("encrypt");

    // Decrypt: recipient decrypts using sender's public key and recipient's secret key
    let pt = decrypt(&ct, &sender_pk, &recipient_sk, &nonce).expect("decrypt");
    assert_eq!(pt, msg);
}

#[test]
fn nonce_randomness_length() {
    let n1 = generate_nonce();
    let n2 = generate_nonce();
    assert_eq!(n1.len(), 24);
    assert_ne!(n1, n2, "nonce should be random");
}
