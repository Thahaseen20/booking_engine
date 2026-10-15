CREATE DATABASE IF NOT EXISTS booking_engine
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE booking_engine;

CREATE TABLE customers (
    customer_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(254) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (customer_id),
    UNIQUE KEY uq_customers_email (email)
) ENGINE = InnoDB;

CREATE TABLE theatres (
    theatre_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(150) NOT NULL,
    address_line VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_region VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country_code CHAR(2) NOT NULL,
    time_zone VARCHAR(64) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (theatre_id),
    KEY ix_theatres_city (city, state_region)
) ENGINE = InnoDB;

CREATE TABLE screens (
    screen_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    theatre_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(80) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (screen_id),
    UNIQUE KEY uq_screens_theatre_name (theatre_id, name),
    CONSTRAINT fk_screens_theatre
        FOREIGN KEY (theatre_id) REFERENCES theatres (theatre_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

CREATE TABLE seats (
    seat_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    screen_id BIGINT UNSIGNED NOT NULL,
    row_label VARCHAR(8) NOT NULL,
    seat_number SMALLINT UNSIGNED NOT NULL,
    seat_type ENUM('standard', 'premium', 'accessible', 'recliner') NOT NULL DEFAULT 'standard',
    PRIMARY KEY (seat_id),
    UNIQUE KEY uq_seats_position (screen_id, row_label, seat_number),
    CONSTRAINT fk_seats_screen
        FOREIGN KEY (screen_id) REFERENCES screens (screen_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

CREATE TABLE movies (
    movie_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    duration_minutes SMALLINT UNSIGNED NOT NULL,
    language VARCHAR(60) NOT NULL,
    certificate VARCHAR(20) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (movie_id),
    CONSTRAINT chk_movies_duration CHECK (duration_minutes > 0)
) ENGINE = InnoDB;

CREATE TABLE shows (
    show_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    screen_id BIGINT UNSIGNED NOT NULL,
    movie_id BIGINT UNSIGNED NOT NULL,
    starts_at DATETIME NOT NULL COMMENT 'Theatre-local wall-clock time',
    ends_at DATETIME NOT NULL COMMENT 'Theatre-local wall-clock time',
    status ENUM('scheduled', 'cancelled', 'completed') NOT NULL DEFAULT 'scheduled',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (show_id),
    UNIQUE KEY uq_shows_screen_start (screen_id, starts_at),
    KEY ix_shows_start_status_screen (starts_at, status, screen_id),
    CONSTRAINT fk_shows_screen
        FOREIGN KEY (screen_id) REFERENCES screens (screen_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_shows_movie
        FOREIGN KEY (movie_id) REFERENCES movies (movie_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT chk_shows_time CHECK (ends_at > starts_at)
) ENGINE = InnoDB;

CREATE TABLE bookings (
    booking_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    customer_id BIGINT UNSIGNED NOT NULL,
    show_id BIGINT UNSIGNED NOT NULL,
    status ENUM('pending', 'held', 'confirmed', 'expired', 'cancelled', 'payment_failed') NOT NULL DEFAULT 'pending',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (booking_id),
    KEY ix_bookings_customer_created (customer_id, created_at),
    KEY ix_bookings_show_status (show_id, status),
    CONSTRAINT fk_bookings_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_bookings_show
        FOREIGN KEY (show_id) REFERENCES shows (show_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

CREATE TABLE show_seats (
    show_seat_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    show_id BIGINT UNSIGNED NOT NULL,
    seat_id BIGINT UNSIGNED NOT NULL,
    inventory_status ENUM('active', 'unavailable') NOT NULL DEFAULT 'active',
    price DECIMAL(10, 2) NOT NULL,
    PRIMARY KEY (show_seat_id),
    UNIQUE KEY uq_show_seats_show_seat (show_id, seat_id),
    CONSTRAINT fk_show_seats_show
        FOREIGN KEY (show_id) REFERENCES shows (show_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_show_seats_seat
        FOREIGN KEY (seat_id) REFERENCES seats (seat_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT chk_show_seats_price CHECK (price >= 0)
) ENGINE = InnoDB;

CREATE TABLE booking_seats (
    show_seat_id BIGINT UNSIGNED NOT NULL,
    booking_id BIGINT UNSIGNED NOT NULL,
    status ENUM('held', 'booked') NOT NULL DEFAULT 'held',
    hold_expires_at DATETIME(6) NULL,
    price_paid DECIMAL(10, 2) NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (show_seat_id),
    KEY ix_booking_seats_booking_status (booking_id, status),
    KEY ix_booking_seats_expiry (status, hold_expires_at),
    CONSTRAINT fk_booking_seats_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_booking_seats_inventory
        FOREIGN KEY (show_seat_id) REFERENCES show_seats (show_seat_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT chk_booking_seats_state CHECK (
        (status = 'held' AND hold_expires_at IS NOT NULL AND price_paid IS NULL)
        OR
        (status = 'booked' AND hold_expires_at IS NULL AND price_paid IS NOT NULL AND price_paid >= 0)
    )
) ENGINE = InnoDB;

CREATE TABLE payments (
    payment_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    booking_id BIGINT UNSIGNED NOT NULL,
    provider VARCHAR(40) NOT NULL,
    provider_payment_id VARCHAR(160) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status ENUM('pending', 'succeeded', 'failed', 'refunded') NOT NULL DEFAULT 'pending',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (payment_id),
    UNIQUE KEY uq_payments_provider_reference (provider, provider_payment_id),
    KEY ix_payments_booking_created (booking_id, created_at),
    CONSTRAINT fk_payments_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT chk_payments_amount CHECK (amount >= 0)
) ENGINE = InnoDB;

CREATE TABLE payment_webhook_events (
    webhook_event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    provider VARCHAR(40) NOT NULL,
    provider_event_id VARCHAR(160) NOT NULL,
    payment_id BIGINT UNSIGNED NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSON NOT NULL,
    processing_status ENUM('received', 'processed', 'ignored', 'failed') NOT NULL DEFAULT 'received',
    received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    processed_at DATETIME(6) NULL,
    PRIMARY KEY (webhook_event_id),
    UNIQUE KEY uq_webhook_provider_event (provider, provider_event_id),
    KEY ix_webhook_payment_received (payment_id, received_at),
    CONSTRAINT fk_webhook_payment
        FOREIGN KEY (payment_id) REFERENCES payments (payment_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

INSERT INTO customers (customer_id, full_name, email)
VALUES (1, 'Aarav Mehta', 'aarav@example.com');

INSERT INTO theatres (
    theatre_id, name, address_line, city, state_region,
    postal_code, country_code, time_zone
)
VALUES (
    1, 'Central Cinema', '42 Market Road', 'Bengaluru', 'Karnataka',
    '560001', 'IN', 'Asia/Kolkata'
);

INSERT INTO screens (screen_id, theatre_id, name)
VALUES (1, 1, 'Screen 1');

INSERT INTO seats (seat_id, screen_id, row_label, seat_number, seat_type)
VALUES
    (1, 1, 'A', 1, 'standard'),
    (2, 1, 'A', 2, 'standard'),
    (3, 1, 'A', 3, 'premium');

INSERT INTO movies (movie_id, title, duration_minutes, language, certificate)
VALUES
    (1, 'The Last Orbit', 128, 'English', 'UA'),
    (2, 'Monsoon Letters', 114, 'Kannada', 'U');

INSERT INTO shows (show_id, screen_id, movie_id, starts_at, ends_at, status)
VALUES
    (1, 1, 1, '2026-10-16 18:30:00', '2026-10-16 20:38:00', 'scheduled'),
    (2, 1, 2, '2026-10-16 21:15:00', '2026-10-16 23:09:00', 'scheduled');

INSERT INTO bookings (booking_id, customer_id, show_id, status)
VALUES (1001, 1, 1, 'held');

INSERT INTO show_seats (
    show_seat_id, show_id, seat_id, inventory_status, price
)
VALUES
    (1, 1, 1, 'active', 250.00),
    (2, 1, 2, 'active', 250.00),
    (3, 1, 3, 'active', 350.00),
    (4, 2, 1, 'active', 220.00),
    (5, 2, 2, 'active', 220.00),
    (6, 2, 3, 'active', 320.00);

INSERT INTO booking_seats (
    show_seat_id, booking_id, status, hold_expires_at, price_paid
)
VALUES (1, 1001, 'held', CURRENT_TIMESTAMP(6) + INTERVAL 12 MINUTE, NULL);

INSERT INTO payments (
    payment_id, booking_id, provider, provider_payment_id,
    amount, currency, status
)
VALUES (
    5001, 1001, 'demo_gateway', 'demo_payment_5001',
    250.00, 'INR', 'pending'
);

INSERT INTO payment_webhook_events (
    webhook_event_id, provider, provider_event_id, payment_id,
    event_type, payload, processing_status
)
VALUES (
    1, 'demo_gateway', 'evt_demo_received_5001', 5001,
    'payment.pending',
    JSON_OBJECT('id', 'evt_demo_received_5001', 'type', 'payment.pending'),
    'received'
);
