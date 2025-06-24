;; Paideia Bazaar - Educational development marketplace
;; A trust-minimized blockchain platform enabling peer-to-peer knowledge transfer through 
;; secure token exchanges. Participants can monetize their insights, schedule learning sessions, 
;; and build reputation through a transparent verification system.

;; ========== CORE SYSTEM METRICS ==========
(define-data-var knowledge-token-rate uint u10)  
(define-data-var contributor-wisdom-threshold uint u100) 
(define-data-var protocol-revenue-share uint u10)
(define-data-var collective-wisdom-repository uint u0) 
(define-data-var wisdom-ecosystem-ceiling uint u1000) 


;; ========== REPUTATION MECHANISM ==========

(define-map contributor-feedback {mentor: principal, learner: principal} uint)
(define-map contributor-metrics principal {quality-score: uint, feedback-count: uint})

;; ========== BULK KNOWLEDGE PACKAGES ==========

(define-map wisdom-bundles {contributor: principal} {units: uint, valuation: uint, incentive-rate: uint})

;; ========== PROTOCOL GOVERNANCE AND STATUS CODES ==========

(define-constant error-insufficient-resources (err u201))
(define-constant error-invalid-wisdom-amount (err u202))
(define-constant protocol-guardian tx-sender)
(define-constant error-unauthorized-guardian (err u200))
(define-constant error-invalid-valuation (err u203))
(define-constant error-zero-threshold (err u209))
(define-constant error-repository-shrinkage (err u210))
(define-constant error-verification-required (err u211))
(define-constant error-quality-threshold (err u212))
(define-constant error-ecosystem-saturation (err u204))
(define-constant error-permission-violation (err u205))
(define-constant error-threshold-exceeded (err u206))
(define-constant error-zero-contribution (err u207))
(define-constant error-excessive-revenue-share (err u208))
(define-constant error-quality-ceiling (err u213))
(define-constant error-incentive-floor (err u214))
(define-constant error-incentive-ceiling (err u215))

;; ========== PARTICIPANT LEDGERS ==========
;; Maps for tracking participant resources and offerings
(define-map wisdom-reserves principal uint)    ;; Participant's available wisdom units
(define-map crystal-holdings principal uint)   ;; Participant's available token balance
(define-map wisdom-marketplace {contributor: principal} {units: uint, valuation: uint})

;; ========== TRUST FRAMEWORK ==========

(define-map validated-contributors principal bool)
(define-map premium-wisdom-offerings {contributor: principal} {units: uint, valuation: uint, validated: bool})

;; ========== COLLABORATIVE LEARNING ==========

(define-map learning-circles uint {facilitator: principal, participants: (list 10 principal), duration: uint, contribution: uint, status: (string-ascii 20)})
(define-data-var circle-identifier uint u0)

;; ========== ECOSYSTEM UTILITIES ==========

(define-private (update-wisdom-repository (units-delta int))
  (let (
    (current-repository (var-get collective-wisdom-repository))
    (new-repository-level (if (< units-delta 0)
                     ;; If reducing units, ensure we don't go below zero
                     (if (>= current-repository (to-uint (- 0 units-delta)))
                         (- current-repository (to-uint (- 0 units-delta)))
                         u0)
                     ;; If adding units
                     (+ current-repository (to-uint units-delta))))
  )
    ;; Ensure we don't exceed the ecosystem capacity
    (asserts! (<= new-repository-level (var-get wisdom-ecosystem-ceiling)) error-ecosystem-saturation)
    ;; Update the repository size
    (var-set collective-wisdom-repository new-repository-level)
    (ok true)))

(define-private (calculate-protocol-share (transaction-value uint))
  (let ((share-percentage (var-get protocol-revenue-share)))
    (/ (* transaction-value share-percentage) u100)))

;; ========== CORE PROTOCOL FUNCTIONS ==========

;; Register new wisdom units to participant's account
(define-public (mint-wisdom-units (units uint))
  (let (
    (participant tx-sender)
    (current-units (default-to u0 (map-get? wisdom-reserves participant)))
    (max-allowed (var-get contributor-wisdom-threshold))
    (minting-cost (* units (var-get knowledge-token-rate)))
    (participant-crystals (default-to u0 (map-get? crystal-holdings participant)))
  )
    ;; Validate the input
    (asserts! (> units u0) error-invalid-wisdom-amount)
    (asserts! (<= (+ current-units units) max-allowed) error-threshold-exceeded)
    (asserts! (>= participant-crystals minting-cost) error-insufficient-resources)

    ;; Update participant's wisdom and crystal balances
    (map-set wisdom-reserves participant (+ current-units units))
    (map-set crystal-holdings participant (- participant-crystals minting-cost))

    ;; Add funds to the guardian's balance
    (map-set crystal-holdings protocol-guardian (+ (default-to u0 (map-get? crystal-holdings protocol-guardian)) minting-cost))

    (ok true)))

;; Make wisdom available for others to acquire
(define-public (offer-wisdom (units uint) (valuation uint))
  (let (
    (current-units (default-to u0 (map-get? wisdom-reserves tx-sender)))
    (currently-offered (get units (default-to {units: u0, valuation: u0} (map-get? wisdom-marketplace {contributor: tx-sender}))))
    (total-offered (+ units currently-offered))
  )
    ;; Validate the input
    (asserts! (> units u0) error-invalid-wisdom-amount)
    (asserts! (> valuation u0) error-invalid-valuation)
    (asserts! (>= current-units total-offered) error-insufficient-resources)

    ;; Update the wisdom repository
    (try! (update-wisdom-repository (to-int units)))

    ;; Update the wisdom marketplace
    (map-set wisdom-marketplace {contributor: tx-sender} {units: total-offered, valuation: valuation})

    (ok true)))

;; Acquire wisdom from another participant
(define-public (acquire-wisdom (contributor principal) (units uint))
  (let (
    (offering (default-to {units: u0, valuation: u0} (map-get? wisdom-marketplace {contributor: contributor})))
    (exchange-value (* units (get valuation offering)))
    (protocol-fee (calculate-protocol-share exchange-value))
    (total-cost (+ exchange-value protocol-fee))
    (contributor-units (default-to u0 (map-get? wisdom-reserves contributor)))
    (learner-crystals (default-to u0 (map-get? crystal-holdings tx-sender)))
    (contributor-crystals (default-to u0 (map-get? crystal-holdings contributor)))
  )
    ;; Verify conditions
    (asserts! (not (is-eq tx-sender contributor)) error-permission-violation)
    (asserts! (> units u0) error-invalid-wisdom-amount)
    (asserts! (>= (get units offering) units) error-insufficient-resources)
    (asserts! (>= contributor-units units) error-insufficient-resources)
    (asserts! (>= learner-crystals total-cost) error-insufficient-resources)

    ;; Update contributor's wisdom balance and available offerings
    (map-set wisdom-reserves contributor (- contributor-units units))
    (map-set wisdom-marketplace {contributor: contributor} 
             {units: (- (get units offering) units), valuation: (get valuation offering)})

    ;; Update token balances
    (map-set crystal-holdings tx-sender (- learner-crystals total-cost))
    (map-set crystal-holdings contributor (+ contributor-crystals exchange-value))
    (map-set wisdom-reserves tx-sender (+ (default-to u0 (map-get? wisdom-reserves tx-sender)) units))

    ;; Add protocol fee to guardian balance
    (map-set crystal-holdings protocol-guardian (+ (default-to u0 (map-get? crystal-holdings protocol-guardian)) protocol-fee))

    (ok true)))

;; Offer validated premium wisdom (requires verification)
(define-public (offer-premium-wisdom (units uint) (valuation uint))
  (let (
    (current-units (default-to u0 (map-get? wisdom-reserves tx-sender)))
    (is-validated (default-to false (map-get? validated-contributors tx-sender)))
    (currently-offered (get units (default-to {units: u0, valuation: u0} (map-get? wisdom-marketplace {contributor: tx-sender}))))
    (total-offered (+ units currently-offered))
  )
    ;; Validate the input
    (asserts! (> units u0) error-invalid-wisdom-amount)
    (asserts! (> valuation u0) error-invalid-valuation)
    (asserts! is-validated error-verification-required)
    (asserts! (>= current-units total-offered) error-insufficient-resources)

    ;; Update the wisdom repository
    (try! (update-wisdom-repository (to-int units)))

    ;; Update regular wisdom offerings
    (map-set wisdom-marketplace {contributor: tx-sender} {units: total-offered, valuation: valuation})

    ;; Update premium wisdom offerings
    (map-set premium-wisdom-offerings {contributor: tx-sender} {units: units, valuation: valuation, validated: true})

    (ok true)))

;; Create a bundled package of wisdom units with incentive
(define-public (create-wisdom-bundle (units uint) (valuation uint) (incentive-rate uint))
  (let (
    (current-units (default-to u0 (map-get? wisdom-reserves tx-sender)))
    (currently-offered (get units (default-to {units: u0, valuation: u0} (map-get? wisdom-marketplace {contributor: tx-sender}))))
    (current-bundle (default-to {units: u0, valuation: u0, incentive-rate: u0} (map-get? wisdom-bundles {contributor: tx-sender})))
    (total-offered (+ units currently-offered))
    (total-bundled-units (+ units (get units current-bundle)))
  )
    ;; Validate the input
    (asserts! (> units u0) error-invalid-wisdom-amount)
    (asserts! (> valuation u0) error-invalid-valuation)
    (asserts! (> incentive-rate u0) error-incentive-floor)
    (asserts! (<= incentive-rate u50) error-incentive-ceiling)
    (asserts! (>= current-units total-offered) error-insufficient-resources)

    ;; Update the wisdom repository
    (try! (update-wisdom-repository (to-int units)))

    ;; Update wisdom availability
    (map-set wisdom-marketplace {contributor: tx-sender} {units: total-offered, valuation: valuation})

    ;; Create or update the bundle offering
    (map-set wisdom-bundles {contributor: tx-sender} {
      units: total-bundled-units, 
      valuation: valuation, 
      incentive-rate: incentive-rate
    })

    (ok true)))

;; Initialize a collaborative learning circle
(define-public (create-learning-circle (learners (list 10 principal)) (duration uint) (contribution uint))
  (let (
    (current-units (default-to u0 (map-get? wisdom-reserves tx-sender)))
    (circle-id (var-get circle-identifier))
    (participant-count (len learners))
    (total-circle-units (* duration participant-count))
  )
    ;; Validate the input
    (asserts! (> duration u0) error-invalid-wisdom-amount)
    (asserts! (> contribution u0) error-invalid-valuation)
    (asserts! (>= current-units total-circle-units) error-insufficient-resources)

    ;; Update the wisdom repository
    (try! (update-wisdom-repository (to-int total-circle-units)))

    ;; Update facilitator's wisdom balance
    (map-set wisdom-reserves tx-sender (- current-units total-circle-units))

    ;; Increment the circle identifier
    (var-set circle-identifier (+ circle-id u1))

    (ok circle-id)))

;; Rate a contributor after wisdom exchange
(define-public (rate-contributor (contributor principal) (rating uint))
  (let (
    (contributor-profile (default-to {quality-score: u0, feedback-count: u0} (map-get? contributor-metrics contributor)))
    (current-score (get quality-score contributor-profile))
    (current-count (get feedback-count contributor-profile))
    (new-score (+ current-score rating))
    (new-count (+ current-count u1))
  )
    ;; Validate the input
    (asserts! (not (is-eq tx-sender contributor)) error-permission-violation)
    (asserts! (>= rating u1) error-quality-threshold)
    (asserts! (<= rating u5) error-quality-ceiling)

    ;; Update the contributor's rating data
    (map-set contributor-feedback {mentor: contributor, learner: tx-sender} rating)
    (map-set contributor-metrics contributor {quality-score: new-score, feedback-count: new-count})

    (ok true)))

;; Deposit crystals into the protocol
(define-public (deposit-crystals (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? crystal-holdings tx-sender)))
    (new-balance (+ current-balance amount))
  )
    ;; Validate the input
    (asserts! (> amount u0) error-zero-contribution)

    ;; Transfer crystals from sender to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    ;; Update participant's crystal balance in the protocol
    (map-set crystal-holdings tx-sender new-balance)

    (ok true)))

;; Withdraw crystals from the protocol
(define-public (withdraw-crystals (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? crystal-holdings tx-sender)))
    (contract-balance (as-contract (stx-get-balance tx-sender)))
  )
    ;; Validate the input
    (asserts! (> amount u0) error-zero-contribution)
    (asserts! (>= current-balance amount) error-insufficient-resources)
    (asserts! (>= contract-balance amount) error-insufficient-resources)

    ;; Transfer crystals from contract to participant
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))

    ;; Update participant's crystal balance in the protocol
    (map-set crystal-holdings tx-sender (- current-balance amount))

    (ok true)))

;; Reclaim offered wisdom that hasn't been acquired
(define-public (reclaim-offered-wisdom (units uint))
  (let (
    (offering (default-to {units: u0, valuation: u0} (map-get? wisdom-marketplace {contributor: tx-sender})))
    (available-units (get units offering))
    (participant-units (default-to u0 (map-get? wisdom-reserves tx-sender)))
  )
    ;; Validate the input
    (asserts! (> units u0) error-invalid-wisdom-amount)
    (asserts! (>= available-units units) error-insufficient-resources)

    ;; Update the participant's offered wisdom
    (map-set wisdom-marketplace {contributor: tx-sender} {
      units: (- available-units units),
      valuation: (get valuation offering)
    })

    ;; Update participant's wisdom balance
    (map-set wisdom-reserves tx-sender (+ participant-units units))

    ;; Handle premium offerings if applicable
    (if (is-some (map-get? premium-wisdom-offerings {contributor: tx-sender}))
        (let (
          (premium-offering (unwrap-panic (map-get? premium-wisdom-offerings {contributor: tx-sender})))
          (premium-units (get units premium-offering))
        )
          (if (>= premium-units units)
              (map-set premium-wisdom-offerings {contributor: tx-sender} {
                units: (- premium-units units),
                valuation: (get valuation premium-offering),
                validated: (get validated premium-offering)
              })
              (map-delete premium-wisdom-offerings {contributor: tx-sender})
          )
        )
        true
    )

    ;; Handle bundled offerings if applicable
    (if (is-some (map-get? wisdom-bundles {contributor: tx-sender}))
        (let (
          (bundle-offering (unwrap-panic (map-get? wisdom-bundles {contributor: tx-sender})))
          (bundle-units (get units bundle-offering))
        )
          (if (>= bundle-units units)
              (map-set wisdom-bundles {contributor: tx-sender} {
                units: (- bundle-units units),
                valuation: (get valuation bundle-offering),
                incentive-rate: (get incentive-rate bundle-offering)
              })
              (map-delete wisdom-bundles {contributor: tx-sender})
          )
        )
        true
    )

    (ok true)))

;; Validate a contributor (guardian only)
(define-public (validate-contributor (contributor principal))
  (begin
    ;; Verify guardian privileges
    (asserts! (is-eq tx-sender protocol-guardian) error-unauthorized-guardian)
    (ok true)))

;; Update protocol configuration (guardian only)
(define-public (reconfigure-protocol (new-token-rate uint) 
                                      (new-revenue-share uint) 
                                      (new-contributor-threshold uint) 
                                      (new-ecosystem-ceiling uint))
  (begin
    ;; Verify guardian privileges
    (asserts! (is-eq tx-sender protocol-guardian) error-unauthorized-guardian)

    ;; Validate the input
    (asserts! (> new-token-rate u0) error-invalid-valuation)
    (asserts! (<= new-revenue-share u30) error-excessive-revenue-share)
    (asserts! (> new-contributor-threshold u0) error-zero-threshold)
    (asserts! (>= new-ecosystem-ceiling (var-get collective-wisdom-repository)) error-repository-shrinkage)

    ;; Update the protocol configuration
    (var-set knowledge-token-rate new-token-rate)
    (var-set protocol-revenue-share new-revenue-share)
    (var-set contributor-wisdom-threshold new-contributor-threshold)
    (var-set wisdom-ecosystem-ceiling new-ecosystem-ceiling)

    (ok true)))

;; Pause a learning circle (guardian or facilitator only)
(define-public (pause-learning-circle (circle-id uint))
  (let (
    (circle (default-to {facilitator: 'SPNWZ5V2TPWGQGVDR6T7B6RQ4XMGZ4PXTEE0VQ0S, participants: (list), duration: u0, contribution: u0, status: "none"} 
             (map-get? learning-circles circle-id)))
    (facilitator (get facilitator circle))
  )
    ;; Verify privileges
    (asserts! (or (is-eq tx-sender protocol-guardian) (is-eq tx-sender facilitator)) error-permission-violation)

    (ok true)))

;; Resume a paused learning circle (guardian or facilitator only)
(define-public (resume-learning-circle (circle-id uint))
  (let (
    (circle (default-to {facilitator: 'SPNWZ5V2TPWGQGVDR6T7B6RQ4XMGZ4PXTEE0VQ0S, participants: (list), duration: u0, contribution: u0, status: "none"} 
             (map-get? learning-circles circle-id)))
    (facilitator (get facilitator circle))
  )
    ;; Verify privileges
    (asserts! (or (is-eq tx-sender protocol-guardian) (is-eq tx-sender facilitator)) error-permission-violation)
    (asserts! (is-eq (get status circle) "paused") error-permission-violation)

    ;; Update the circle status
    (map-set learning-circles circle-id {
      facilitator: facilitator,
      participants: (get participants circle),
      duration: (get duration circle),
      contribution: (get contribution circle),
      status: "active"
    })

    (ok true)))

;; Complete a learning circle (facilitator only)
(define-public (complete-learning-circle (circle-id uint))
  (let (
    (circle (default-to {facilitator: 'SPNWZ5V2TPWGQGVDR6T7B6RQ4XMGZ4PXTEE0VQ0S, participants: (list), duration: u0, contribution: u0, status: "none"} 
             (map-get? learning-circles circle-id)))
    (facilitator (get facilitator circle))
  )
    ;; Verify privileges
    (asserts! (is-eq tx-sender facilitator) error-permission-violation)

    (ok true)))

