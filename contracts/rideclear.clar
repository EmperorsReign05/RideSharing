;; rideclear.clar
;; A decentralized ride-sharing contract for transparent and secure ride management.
;; This contract holds fares in escrow and releases them upon ride completion.

;; ---------------------------------------------------------
;; Constants and Errors
;; ---------------------------------------------------------
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_INVALID_FARE (err u101))
(define-constant ERR_RIDE_NOT_FOUND (err u102))
(define-constant ERR_UNAUTHORIZED (err u103))
(define-constant ERR_RIDE_ALREADY_COMPLETED (err u104))

;; ---------------------------------------------------------
;; Data Storage
;; ---------------------------------------------------------
;; A counter to ensure each ride gets a unique ID
(define-data-var last-ride-id uint u0)

;; A map to store the details of each ride request
;; Key: ride-id (uint)
;; Value: A tuple containing ride data
(define-map rides uint {
    passenger: principal,
    driver: (optional principal),
    fare: uint,
    status: (string-ascii 12) ;; "pending", "completed"
})

;; ---------------------------------------------------------
;; Public Functions
;; ---------------------------------------------------------

;; @desc      Called by a passenger to request a ride and lock the fare in escrow.
;; @param     driver          The principal of the ride's driver.
;; @param     fare            The amount of STX for the ride.
;; @returns   (ok uint)       The ID of the newly created ride.
(define-public (request-ride (driver principal) (fare uint))
    (begin
        ;; Ensure the fare is a positive amount
        (asserts! (> fare u0) ERR_INVALID_FARE)

        ;; Lock the passenger's funds (in STX) into this contract
        (try! (stx-transfer? fare tx-sender (as-contract tx-sender)))

        ;; Get the ID for this new ride and increment the counter
        (let ((ride-id (+ u1 (var-get last-ride-id))))
            ;; Store the ride details in the 'rides' map
            (map-set rides ride-id {
                passenger: tx-sender,
                driver: (some driver),
                fare: fare,
                status: "pending"
            })
            (var-set last-ride-id ride-id)
            ;; Return the new ride ID
            (ok ride-id)
        )
    )
)

;; @desc      Called by the passenger to confirm ride completion and pay the driver.
;; @param     ride-id         The ID of the ride to complete.
;; @returns   (ok bool)       True if the payment is successful.
(define-public (complete-ride (ride-id uint))
    (begin
        ;; Retrieve the ride details from the map, otherwise return an error
        (let ((ride-details (unwrap! (map-get? rides ride-id) ERR_RIDE_NOT_FOUND)))

            ;; Check that the person calling this function is the passenger who booked it
            (asserts! (is-eq tx-sender (get passenger ride-details)) ERR_UNAUTHORIZED)
            ;; Check that the ride has not already been completed
            (asserts! (is-eq (get status ride-details) "pending") ERR_RIDE_ALREADY_COMPLETED)

            ;; Transfer the fare from the contract's escrow to the driver
            (let ((fare (get fare ride-details))
                  (driver (unwrap-panic (get driver ride-details))))
                (try! (as-contract (stx-transfer? fare tx-sender driver)))

                ;; Update the ride status to "completed" to prevent double payment
                (map-set rides ride-id
                    (merge ride-details {status: "completed"})
                )
                (ok true)
            )
        )
    )
)