use crypto_core::{encrypt, decrypt, generate_nonce};

#[test]
fn roundtrip_echo_stub() {
    let msg = b"hello";
    let nonce = generate_nonce();
    let ct = encrypt(msg, b"pub", b"sec", &nonce).expect("encrypt");
    let pt = decrypt(&ct, b"pub", b"sec", &nonce).expect("decrypt");
    assert_eq!(pt, msg);
}

#[test]
fn nonce_randomness_length() {
    let n1 = generate_nonce();
    let n2 = generate_nonce();
    assert_eq!(n1.len(), 24);
    assert_ne!(n1, n2, "nonce should be random");
}

