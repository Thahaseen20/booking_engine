# High-Concurrency Booking Engine

MySQL 8.0.16+ schema and query for listing scheduled movie shows at a theatre on a local calendar date. The schema keeps showtimes in the theatre's local time; `theatres.time_zone` records the IANA time zone for display and application-level date handling.

## Entities and attributes

| Table | Attributes |
|---|---|
| `customers` | `customer_id` (PK), `full_name`, `email` (unique), `created_at` |
| `theatres` | `theatre_id` (PK), `name`, `address_line`, `city`, `state_region`, `postal_code`, `country_code`, `time_zone`, `created_at` |
| `screens` | `screen_id` (PK), `theatre_id` (FK), `name`, `created_at`; screen names are unique within a theatre |
| `seats` | `seat_id` (PK), `screen_id` (FK), `row_label`, `seat_number`, `seat_type`; a seat position is unique within a screen |
| `movies` | `movie_id` (PK), `title`, `duration_minutes`, `language`, `certificate`, `created_at` |
| `shows` | `show_id` (PK), `screen_id` (FK), `movie_id` (FK), `starts_at`, `ends_at`, `status`, `created_at` |
| `bookings` | `booking_id` (PK), `customer_id` (FK), `show_id` (FK), `status`, `created_at`, `updated_at` |
| `show_seats` | `show_seat_id` (PK), `show_id` and `seat_id` (FKs, unique together), `inventory_status`, `price` |
| `booking_seats` | `show_seat_id` (PK and FK to inventory), `booking_id` (FK), `status` (`held` or `booked`), `hold_expires_at`, `price_paid`, `created_at`; the primary key allows at most one claim per show-seat |
| `payments` | `payment_id` (PK), `booking_id` (FK), `provider`, `provider_payment_id`, `amount`, `currency`, `status`, `created_at`, `updated_at`; provider payment reference is unique |
| `payment_webhook_events` | `webhook_event_id` (PK), `provider`, `provider_event_id`, `payment_id` (nullable FK), `event_type`, `payload`, `processing_status`, `received_at`, `processed_at`; provider event reference is unique for idempotency |

## P1 — Schema and sample data

The complete, executable DDL and sample inserts are in [`schema.sql`](./schema.sql). Run it in MySQL 8.0.16 or newer:

```sh
mysql -u your_user -p < schema.sql
```

The schema is normalized: seat coordinates are stored once per screen, movie and theatre details are not repeated in show rows, and booking/payment/webhook facts have separate relations. Each column is atomic (1NF); non-key attributes depend on the whole key (2NF); transitive dependencies are kept in their entity tables (3NF). Each non-trivial functional dependency in a base table is determined by a candidate key (BCNF). In particular, seat claims reference a surrogate `show_seat_id` rather than repeating `show_id` alongside `booking_id`. The theatre-to-screen-to-seat and movie-to-show relationships are represented by foreign keys rather than copied descriptive fields.

## Concurrency and hold strategy

`show_seats` is the authoritative inventory: create one row for every seat offered for each show. `booking_seats` records the current claim on that inventory row, either a temporary hold or a confirmed booking. A seat is available when it has no claim, or only an expired hold, and its inventory status is `active`. Use Redis for fast, short-lived coordination (for example, a key scoped to `show_id` and `seat_id` with a random hold token and TTL), but never treat Redis as the source of truth. Redis expiry is not a durable booking decision.

For a hold request:

1. Create the booking in a short MySQL transaction, then select the requested `show_seats` rows with `SELECT ... FOR UPDATE`, in ascending `seat_id` order. Verify all requested rows exist and belong to the booking's show. A consistent lock order reduces deadlocks.
2. For every selected seat, reject `unavailable` inventory and any existing booked claim. An existing held claim is reusable only if its `hold_expires_at <= NOW(6)`. If any requested seat is unavailable, roll back the entire transaction.
3. Insert or replace all expired/missing claims in `booking_seats` with status `held` and a common expiry, and mark the booking `held`; commit. Use a conditional update as an additional guard and verify the affected-row count matches the requested seat count.
4. Return the hold token/booking ID and expiry to the client. The token is an authorization secret and should be unguessable; persist only a hash if token-based authorization is used. Payment confirmation and hold release must check the booking ID, current state, and unexpired deadline under row locks.
5. An expiry worker finds expired held claims, locks the associated inventory rows and booking, and releases them only if they are still held and expired. This makes a delayed worker safe: a seat already confirmed or renewed is not released. Run expiry and confirmation transitions transactionally.

On successful payment, process the event and booking in one transaction: insert the unique provider event, lock the booking and its held claims, verify that every hold is still valid, update the claims to `booked`, copy the offered prices into `price_paid`, mark the booking `confirmed`, and mark the payment/event processed. A duplicate `(provider, provider_event_id)` is an already-seen event and must not repeat the transition. If a success event arrives after the hold has expired, do not sell the seat; route the payment to the provider's refund/compensation flow.

The database row locks serialize competing hold attempts for the same inventory rows. The unique key on `show_seats(show_id, seat_id)` ensures one inventory row per show-seat, and the primary key on `booking_seats(show_seat_id)` is the final database guard against two simultaneous claims. Keep transactions short; do not call Redis or a payment provider while holding database locks. Retry deadlocks with a bounded retry policy.

## P2 — Shows at a theatre on a date

[`queries.sql`](./queries.sql) contains the executable query. Set the MySQL session variables `@theatre_id` and `@show_date` to the requested theatre ID and local date before running it. The half-open date range preserves use of the `starts_at` index and includes every show starting on that date.

```sql
SET @theatre_id = 1;
SET @show_date = '2026-10-16';

SELECT
    m.movie_id,
    m.title AS movie_title,
    sh.show_id,
    sh.starts_at AS show_start,
    sh.ends_at AS show_end
FROM theatres AS t
JOIN screens AS sc
    ON sc.theatre_id = t.theatre_id
JOIN shows AS sh
    ON sh.screen_id = sc.screen_id
JOIN movies AS m
    ON m.movie_id = sh.movie_id
WHERE t.theatre_id = @theatre_id
  AND sh.status = 'scheduled'
  AND sh.starts_at >= CAST(@show_date AS DATE)
  AND sh.starts_at < DATE_ADD(CAST(@show_date AS DATE), INTERVAL 1 DAY)
ORDER BY sh.starts_at, m.title, sh.show_id;
```

The showtime is a theatre-local `DATETIME`. If the application accepts dates in another time zone, convert the selected date to the theatre's local calendar date before setting `@show_date`. The `(screen_id, starts_at)` index supports per-screen date-range lookups.
