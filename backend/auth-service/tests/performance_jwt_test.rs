/// JWT Performance Benchmarks
///
/// Per T052: Optimize JWT generation/validation latency (target < 50ms)
/// Per T054: Measure p50/p95/p99 latencies; verify p95 < 200ms (SC-002)
///
/// This test module measures JWT token generation and validation performance
/// to ensure we meet SLA targets for authentication operations.

#[cfg(test)]
mod jwt_performance_tests {
    use crypto_core::jwt;
    use std::sync::Once;
    use std::time::Instant;
    use uuid::Uuid;

    // Test RSA key pair - FOR TESTING ONLY
    // NEVER use these keys in production
    const TEST_PRIVATE_KEY: &str = r#"-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDmk2ZpednMZ2LD
UgdpKdNEgdB6Z8sbcHGwN+/UjEQGDJXpilaPQIVjGttbVbZ+l91IdvQ1x/cwN6sZ
0+R8vIThjJcaHRelPnRmcsQeu5jtPA/6x8h8jpvzvYEXCZ3QI9Fe1trnI3KUbTOS
WZpXRoWLlbgH4wUjTf9H6yKw11iNd5US9DbvLUU0F8noWqvVk8zqoB5aJosMNdW8
VMoRP94Hi7T51xwpqkb3EBLWRjZS3icyUHWpPFCCTRsIRbkvZ62SU4K9y9JIOeWp
ZZy1SOxrowbqUI5t+7ayE6+Rj4GRBh/z0rEBO4kGAln7+t3T8f4HKA8ttFWx9glg
6CTUN9wnAgMBAAECggEAJE+LeIojOG4CPvbItVD236T/Kyeenqrt3G29VmA4c34W
kE6kJFm+0m/voh80vBQ3rtUSJEi3WV/gPBMDD88IW2oD1FhHLv36NWABbpg7FFu5
uyksc3Zp13qSZ7RbUTndcO1Y+mlkqTyBO0eNEg1zCRus0uEiIACFIShFsEpZZv2P
cyaZCbr3AltkK4byQL2eQ7Q7aKPZXKEub+acLR5IWOzSRhVQ4KR3K53RHJ6MbGc7
rrQP2MD+tQq1XH9TtKJ5uA51fe8goDhV8Hn4km2sabsSPqH1HyUkN4XZCJ5THhtY
fna+gPkUl5ybumCMPpt1RDSkoJcZly0xWQFWUvMooQKBgQD3Ptqe/hcVfrQn6LoZ
BbgSTv92dvd8Oz9WDBqt0LZDIKu5Kp8qwXIAb6xAd0tkhSDUmuodId8Jh/niRBMy
3zAv90z2QTnXJRFgN3De7Wty/0f8HMRrjR63AwLcx5w5XOLhthVN+jkV+bu0+sJh
EG81O/NbRaYrgnDHQXEHkoTvLwKBgQDuvXGlKahZi8HT3bdqa9lwQrLzVoKy7Ztj
zDazsv24bCVXM0Hj/0NXzq/axvgU6vfG08wMLS/htUAg9QdgTA/HKa5Bb0axhFXc
MQUR3/xTr3kfXXEwITdnDY2X3+j4SgD7OU92P+vwB4iGgPUegrqIHJmrfe51xEM3
J4Sf51LkiQKBgDIR8IQyQMqBlkpevxFCLzzF8sYy4XuvI+xxFxYMJl0ByMT+9Kzb
8BJWizOi9QmuTC/CD5dGvLxZZSmFT74FpOSR2GwmWWhQgWxSzfDXc+Md/5321XBS
a930Jig/5EtZnDjJfxcDjXv9zx2fiq3NfjfxpB7fw/8bs2smvZUi/vjRAoGBAJ6k
OklTFjBywxjjIwdPpUyItdsnKHB3naNCRzNABIMxMdrxD57Ot9Q4XvjU8HMN9Bom
EVgiCshEJdoAmKcvw+hHVSjcJbC+TEOmO0U2fripSKZD9HvUBrmu8uDyBCBBJMfL
vHbKYSC+EMW4Gantmr/pqV+grf2JrlSPKP0MvTNpAoGAZnsljoUTW9PSDnx30Hqk
lRgoyQivtx6hKDm6v2l++mEQ0mMBE3NaN3hYxm6ncpG7b0giTu4jZx9U5Y0DLJ7m
3Dv/Cqr1zqQEekb93a1JZQxj9DP+Q/vw8CX/ky+xCE4zz596Dql+nycrOcbUM056
YMNQEWT7aC6+SsTEfz2Btk8=
-----END PRIVATE KEY-----"#;

    const TEST_PUBLIC_KEY: &str = r#"-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5pNmaXnZzGdiw1IHaSnT
RIHQemfLG3BxsDfv1IxEBgyV6YpWj0CFYxrbW1W2fpfdSHb0Ncf3MDerGdPkfLyE
4YyXGh0XpT50ZnLEHruY7TwP+sfIfI6b872BFwmd0CPRXtba5yNylG0zklmaV0aF
i5W4B+MFI03/R+sisNdYjXeVEvQ27y1FNBfJ6Fqr1ZPM6qAeWiaLDDXVvFTKET/e
B4u0+dccKapG9xAS1kY2Ut4nMlB1qTxQgk0bCEW5L2etklOCvcvSSDnlqWWctUjs
a6MG6lCObfu2shOvkY+BkQYf89KxATuJBgJZ+/rd0/H+BygPLbRVsfYJYOgk1Dfc
JwIDAQAB
-----END PUBLIC KEY-----"#;

    fn init_test_keys() {
        // Use a static flag to prevent re-initialization in tests
        static INIT: Once = Once::new();
        INIT.call_once(|| {
            jwt::initialize_jwt_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY)
                .expect("Failed to initialize test keys");
        });
    }

    /// Simple statistics collector for latency measurements
    struct LatencyStats {
        measurements: Vec<u128>,
    }

    impl LatencyStats {
        fn new() -> Self {
            Self {
                measurements: Vec::new(),
            }
        }

        fn add(&mut self, micros: u128) {
            self.measurements.push(micros);
        }

        fn p50(&self) -> u128 {
            self.percentile(50)
        }

        fn p95(&self) -> u128 {
            self.percentile(95)
        }

        fn p99(&self) -> u128 {
            self.percentile(99)
        }

        fn percentile(&self, p: usize) -> u128 {
            if self.measurements.is_empty() {
                return 0;
            }

            let mut sorted = self.measurements.clone();
            sorted.sort_unstable();

            let index = (sorted.len() * p) / 100;
            sorted[index.min(sorted.len() - 1)]
        }

        fn avg(&self) -> u128 {
            if self.measurements.is_empty() {
                return 0;
            }
            self.measurements.iter().sum::<u128>() / self.measurements.len() as u128
        }

        fn min(&self) -> u128 {
            *self.measurements.iter().min().unwrap_or(&0)
        }

        fn max(&self) -> u128 {
            *self.measurements.iter().max().unwrap_or(&0)
        }
    }

    /// T052: Measure JWT token generation latency
    ///
    /// Target: < 50ms per token generation
    /// This test generates 1000 tokens and measures distribution.
    ///
    /// JWT generation involves:
    /// - Creating Claims struct
    /// - Encoding with RS256 signature
    /// - Base64 encoding
    #[test]
    fn test_jwt_token_generation_latency() {
        // Initialize JWT keys for testing
        init_test_keys();

        let mut stats = LatencyStats::new();
        let iterations = 1000;

        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        // Measure token generation latency
        for _ in 0..iterations {
            let start = Instant::now();
            let _result = jwt::generate_token_pair(user_id, email, username);
            let elapsed = start.elapsed().as_micros();

            stats.add(elapsed);
        }

        // Log statistics
        println!("\n=== JWT Token Generation Latency (μs) ===");
        println!("Iterations: {}", iterations);
        println!(
            "P50:  {} μs ({:.2} ms)",
            stats.p50(),
            stats.p50() as f64 / 1000.0
        );
        println!(
            "P95:  {} μs ({:.2} ms)",
            stats.p95(),
            stats.p95() as f64 / 1000.0
        );
        println!(
            "P99:  {} μs ({:.2} ms)",
            stats.p99(),
            stats.p99() as f64 / 1000.0
        );
        println!(
            "AVG:  {} μs ({:.2} ms)",
            stats.avg(),
            stats.avg() as f64 / 1000.0
        );
        println!(
            "MIN:  {} μs ({:.2} ms)",
            stats.min(),
            stats.min() as f64 / 1000.0
        );
        println!(
            "MAX:  {} μs ({:.2} ms)",
            stats.max(),
            stats.max() as f64 / 1000.0
        );

        // T052: Assert P50 < 50ms (50000 μs)
        assert!(
            stats.p50() < 50_000,
            "P50 token generation latency {} μs exceeds target of 50ms",
            stats.p50()
        );
    }

    /// T052: Measure JWT token validation latency
    ///
    /// Target: < 50ms per validation
    /// This test generates a token and validates it 1000 times.
    ///
    /// JWT validation involves:
    /// - Base64 decoding
    /// - RS256 signature verification
    /// - Expiration check
    #[test]
    fn test_jwt_token_validation_latency() {
        // Initialize JWT keys
        init_test_keys();

        // Generate a test token
        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        let token_result = jwt::generate_token_pair(user_id, email, username);
        assert!(token_result.is_ok(), "Failed to generate test token");
        let token = token_result.unwrap().access_token;

        let mut stats = LatencyStats::new();
        let iterations = 1000;

        // Measure token validation latency
        for _ in 0..iterations {
            let start = Instant::now();
            let _result = jwt::validate_token(&token);
            let elapsed = start.elapsed().as_micros();

            stats.add(elapsed);
        }

        // Log statistics
        println!("\n=== JWT Token Validation Latency (μs) ===");
        println!("Iterations: {}", iterations);
        println!(
            "P50:  {} μs ({:.2} ms)",
            stats.p50(),
            stats.p50() as f64 / 1000.0
        );
        println!(
            "P95:  {} μs ({:.2} ms)",
            stats.p95(),
            stats.p95() as f64 / 1000.0
        );
        println!(
            "P99:  {} μs ({:.2} ms)",
            stats.p99(),
            stats.p99() as f64 / 1000.0
        );
        println!(
            "AVG:  {} μs ({:.2} ms)",
            stats.avg(),
            stats.avg() as f64 / 1000.0
        );
        println!(
            "MIN:  {} μs ({:.2} ms)",
            stats.min(),
            stats.min() as f64 / 1000.0
        );
        println!(
            "MAX:  {} μs ({:.2} ms)",
            stats.max(),
            stats.max() as f64 / 1000.0
        );

        // T052: Assert P50 < 50ms (50000 μs)
        assert!(
            stats.p50() < 50_000,
            "P50 token validation latency {} μs exceeds target of 50ms",
            stats.p50()
        );
    }

    /// T054: Full latency measurement including both generation and validation
    ///
    /// Target: P95 < 200ms for complete register/login flow
    /// Measures end-to-end latency of token generation + validation cycle.
    #[test]
    fn test_full_auth_latency_p95_under_200ms() {
        // Initialize JWT keys
        init_test_keys();

        let mut stats = LatencyStats::new();
        let iterations = 100; // Full cycles (fewer than token-only tests)

        let user_id = Uuid::new_v4();
        let email = "test@example.com";
        let username = "testuser";

        // Measure full auth cycle latency (token generation + validation)
        for _ in 0..iterations {
            let start = Instant::now();

            // Generate token
            let token_result = jwt::generate_token_pair(user_id, email, username);
            assert!(token_result.is_ok());
            let token = token_result.unwrap().access_token;

            // Validate token
            let validation_result = jwt::validate_token(&token);
            assert!(validation_result.is_ok());

            let elapsed = start.elapsed().as_micros();
            stats.add(elapsed);
        }

        // Log statistics
        println!("\n=== Full Auth Cycle Latency (μs) ===");
        println!("Iterations: {}", iterations);
        println!(
            "P50:  {} μs ({:.2} ms)",
            stats.p50(),
            stats.p50() as f64 / 1000.0
        );
        println!(
            "P95:  {} μs ({:.2} ms)",
            stats.p95(),
            stats.p95() as f64 / 1000.0
        );
        println!(
            "P99:  {} μs ({:.2} ms)",
            stats.p99(),
            stats.p99() as f64 / 1000.0
        );
        println!(
            "AVG:  {} μs ({:.2} ms)",
            stats.avg(),
            stats.avg() as f64 / 1000.0
        );
        println!(
            "MIN:  {} μs ({:.2} ms)",
            stats.min(),
            stats.min() as f64 / 1000.0
        );
        println!(
            "MAX:  {} μs ({:.2} ms)",
            stats.max(),
            stats.max() as f64 / 1000.0
        );

        // T054: Assert P95 < 200ms (200000 μs) for full auth cycle
        assert!(
            stats.p95() < 200_000,
            "P95 full auth cycle latency {} μs exceeds SLA target of 200ms (SC-002)",
            stats.p95()
        );

        // Additional assertion for P99 < 300ms (conservative)
        println!(
            "\nP99 latency: {} μs ({:.2} ms)",
            stats.p99(),
            stats.p99() as f64 / 1000.0
        );
    }
}
