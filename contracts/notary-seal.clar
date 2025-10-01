;; Legal Document Notarization System - Notary Seal Contract
;; Manages document authentication, identity verification, and immutable record keeping

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-already-notarized (err u102))
(define-constant err-invalid-document (err u103))
(define-constant err-notary-not-found (err u104))
(define-constant err-notary-suspended (err u105))
(define-constant err-invalid-signature (err u106))
(define-constant err-document-not-found (err u107))
(define-constant err-verification-failed (err u108))

;; Data Variables
(define-data-var next-document-id uint u1)
(define-data-var next-notary-id uint u1)
(define-data-var total-notarizations uint u0)

;; Data Maps

;; Notary registry with identity verification and status management
(define-map notaries
    { notary-id: uint }
    {
        principal: principal,
        name: (string-utf8 50),
        license-number: (string-utf8 30),
        jurisdiction: (string-utf8 50),
        public-key: (buff 33),
        status: (string-utf8 20), ;; "active", "suspended", "revoked"
        registration-date: uint,
        last-activity: uint,
        notarization-count: uint
    }
)

;; Document registry with comprehensive metadata
(define-map documents
    { document-id: uint }
    {
        document-hash: (buff 32),
        document-type: (string-utf8 50),
        title: (string-utf8 100),
        submitter: principal,
        notary-id: uint,
        timestamp: uint,
        block-height: uint,
        signature: (buff 65),
        status: (string-utf8 20), ;; "pending", "notarized", "expired", "revoked"
        expiry-date: (optional uint),
        compliance-flags: (list 10 (string-utf8 30))
    }
)

;; Audit trail for compliance and regulatory requirements
(define-map audit-trail
    { document-id: uint, action-id: uint }
    {
        action-type: (string-utf8 30),
        actor: principal,
        timestamp: uint,
        details: (string-utf8 200),
        previous-status: (string-utf8 20),
        new-status: (string-utf8 20)
    }
)

;; Document access control for privacy and security
(define-map document-access
    { document-id: uint, accessor: principal }
    {
        permission-level: (string-utf8 20), ;; "read", "verify", "admin"
        granted-by: principal,
        granted-at: uint,
        expires-at: (optional uint)
    }
)

;; Notary performance metrics for quality assurance
(define-map notary-metrics
    { notary-id: uint }
    {
        total-notarizations: uint,
        successful-verifications: uint,
        failed-verifications: uint,
        average-processing-time: uint,
        compliance-score: uint,
        last-audit-date: uint
    }
)

;; Public Functions

;; Register a new notary with comprehensive identity verification
(define-public (register-notary 
    (name (string-utf8 50))
    (license-number (string-utf8 30))
    (jurisdiction (string-utf8 50))
    (public-key (buff 33))
    )
    (let 
        (
            (notary-id (var-get next-notary-id))
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        ;; Store notary information
        (map-set notaries
            { notary-id: notary-id }
            {
                principal: tx-sender,
                name: name,
                license-number: license-number,
                jurisdiction: jurisdiction,
                public-key: public-key,
                status: u"active",
                registration-date: current-time,
                last-activity: current-time,
                notarization-count: u0
            }
        )
        
        ;; Initialize notary metrics
        (map-set notary-metrics
            { notary-id: notary-id }
            {
                total-notarizations: u0,
                successful-verifications: u0,
                failed-verifications: u0,
                average-processing-time: u0,
                compliance-score: u100,
                last-audit-date: current-time
            }
        )
        
        ;; Increment next notary ID
        (var-set next-notary-id (+ notary-id u1))
        
        (ok notary-id)
    )
)

;; Submit a document for notarization with comprehensive metadata
(define-public (submit-document
    (document-hash (buff 32))
    (document-type (string-utf8 50))
    (title (string-utf8 100))
    (compliance-flags (list 10 (string-utf8 30)))
    )
    (let 
        (
            (document-id (var-get next-document-id))
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
            (current-height block-height)
        )
        ;; Store document information
        (map-set documents
            { document-id: document-id }
            {
                document-hash: document-hash,
                document-type: document-type,
                title: title,
                submitter: tx-sender,
                notary-id: u0, ;; Will be assigned during notarization
                timestamp: current-time,
                block-height: current-height,
                signature: 0x00, ;; Will be added during notarization
                status: u"pending",
                expiry-date: none,
                compliance-flags: compliance-flags
            }
        )
        
        ;; Grant submitter full access to their document
        (map-set document-access
            { document-id: document-id, accessor: tx-sender }
            {
                permission-level: u"admin",
                granted-by: tx-sender,
                granted-at: current-time,
                expires-at: none
            }
        )
        
        ;; Create audit trail entry
        (map-set audit-trail
            { document-id: document-id, action-id: u1 }
            {
                action-type: u"document_submitted",
                actor: tx-sender,
                timestamp: current-time,
                details: u"Document submitted for notarization",
                previous-status: u"none",
                new-status: u"pending"
            }
        )
        
        ;; Increment next document ID
        (var-set next-document-id (+ document-id u1))
        
        (ok document-id)
    )
)

;; Notarize a document with digital signature and verification
(define-public (notarize-document
    (document-id uint)
    (notary-id uint)
    (signature (buff 65))
    (expiry-days (optional uint))
    )
    (let 
        (
            (document-info (unwrap! (map-get? documents { document-id: document-id }) err-document-not-found))
            (notary-info (unwrap! (map-get? notaries { notary-id: notary-id }) err-notary-not-found))
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
            (expiry-date (match expiry-days
                some-days (some (+ current-time (* some-days u86400)))
                none
            ))
        )
        ;; Verify notary is active
        (asserts! (is-eq (get status notary-info) u"active") err-notary-suspended)
        
        ;; Verify document is pending
        (asserts! (is-eq (get status document-info) u"pending") err-already-notarized)
        
        ;; Verify signature is valid (simplified check)
        (asserts! (not (is-eq signature 0x00)) err-invalid-signature)
        
        ;; Update document with notarization details
        (map-set documents
            { document-id: document-id }
            (merge document-info {
                notary-id: notary-id,
                signature: signature,
                status: u"notarized",
                expiry-date: expiry-date
            })
        )
        
        ;; Update notary activity
        (map-set notaries
            { notary-id: notary-id }
            (merge notary-info {
                last-activity: current-time,
                notarization-count: (+ (get notarization-count notary-info) u1)
            })
        )
        
        ;; Update notary metrics
        (let ((current-metrics (default-to 
                {
                    total-notarizations: u0,
                    successful-verifications: u0,
                    failed-verifications: u0,
                    average-processing-time: u0,
                    compliance-score: u100,
                    last-audit-date: current-time
                }
                (map-get? notary-metrics { notary-id: notary-id })
            )))
            (map-set notary-metrics
                { notary-id: notary-id }
                (merge current-metrics {
                    total-notarizations: (+ (get total-notarizations current-metrics) u1),
                    successful-verifications: (+ (get successful-verifications current-metrics) u1)
                })
            )
        )
        
        ;; Create audit trail entry
        (map-set audit-trail
            { document-id: document-id, action-id: u2 }
            {
                action-type: u"document_notarized",
                actor: (get principal notary-info),
                timestamp: current-time,
                details: u"Document successfully notarized",
                previous-status: u"pending",
                new-status: u"notarized"
            }
        )
        
        ;; Update total notarizations counter
        (var-set total-notarizations (+ (var-get total-notarizations) u1))
        
        (ok true)
    )
)

;; Verify document authenticity and integrity
(define-public (verify-document
    (document-id uint)
    (provided-hash (buff 32))
    )
    (let 
        (
            (document-info (unwrap! (map-get? documents { document-id: document-id }) err-document-not-found))
            (stored-hash (get document-hash document-info))
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        )
        ;; Check if document is notarized
        (asserts! (is-eq (get status document-info) u"notarized") err-verification-failed)
        
        ;; Verify hash matches
        (asserts! (is-eq stored-hash provided-hash) err-verification-failed)
        
        ;; Check if document has not expired
        (match (get expiry-date document-info)
            some-expiry (asserts! (< current-time some-expiry) err-verification-failed)
            true
        )
        
        ;; Update verification metrics
        (let 
            (
                (notary-id (get notary-id document-info))
                (current-metrics (unwrap-panic (map-get? notary-metrics { notary-id: notary-id })))
            )
            (map-set notary-metrics
                { notary-id: notary-id }
                (merge current-metrics {
                    successful-verifications: (+ (get successful-verifications current-metrics) u1)
                })
            )
        )
        
        (ok {
            document-id: document-id,
            verified: true,
            notary-id: (get notary-id document-info),
            timestamp: (get timestamp document-info),
            expiry-date: (get expiry-date document-info)
        })
    )
)

;; Grant access to document for specific principal
(define-public (grant-document-access
    (document-id uint)
    (accessor principal)
    (permission-level (string-utf8 20))
    (expires-in-days (optional uint))
    )
    (let 
        (
            (document-info (unwrap! (map-get? documents { document-id: document-id }) err-document-not-found))
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
            (expiry-time (match expires-in-days
                some-days (some (+ current-time (* some-days u86400)))
                none
            ))
        )
        ;; Only document submitter can grant access
        (asserts! (is-eq tx-sender (get submitter document-info)) err-not-authorized)
        
        ;; Set access permissions
        (map-set document-access
            { document-id: document-id, accessor: accessor }
            {
                permission-level: permission-level,
                granted-by: tx-sender,
                granted-at: current-time,
                expires-at: expiry-time
            }
        )
        
        (ok true)
    )
)

;; Read-only Functions

;; Get document information
(define-read-only (get-document (document-id uint))
    (map-get? documents { document-id: document-id })
)

;; Get notary information
(define-read-only (get-notary (notary-id uint))
    (map-get? notaries { notary-id: notary-id })
)

;; Get document audit trail
(define-read-only (get-audit-trail (document-id uint) (action-id uint))
    (map-get? audit-trail { document-id: document-id, action-id: action-id })
)

;; Check document access permissions
(define-read-only (check-document-access (document-id uint) (accessor principal))
    (map-get? document-access { document-id: document-id, accessor: accessor })
)

;; Get notary metrics
(define-read-only (get-notary-metrics (notary-id uint))
    (map-get? notary-metrics { notary-id: notary-id })
)

;; Get total system statistics
(define-read-only (get-system-stats)
    {
        total-documents: (- (var-get next-document-id) u1),
        total-notaries: (- (var-get next-notary-id) u1),
        total-notarizations: (var-get total-notarizations)
    }
)

;; Verify document hash without full verification process
(define-read-only (check-document-hash (document-id uint) (provided-hash (buff 32)))
    (match (map-get? documents { document-id: document-id })
        document-info (is-eq (get document-hash document-info) provided-hash)
        false
    )
)


;; title: notary-seal
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

