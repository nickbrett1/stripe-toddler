# Stripe Toddler

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/nickbrett1/stripe-toddler/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/nickbrett1/stripe-toddler/tree/main)

A simple, fun, and colorful point-of-sale system designed for a 3-year-old toddler, built to explore and learn about Stripe's APIs and services.

## Goals and Overview

The project aims to achieve two primary goals:

1. Provide a hands-on learning experience with Stripe APIs, Stripe Terminal, and Cloudflare Workers (using Rust).
2. Create an engaging, easy-to-use iPad point-of-sale (POS) experience for a toddler to "sell" household items and toys.

The system features:

- **iPad POS App:** A bright, colorful iOS app with large buttons and visual feedback, connecting to a Bluetooth barcode scanner and a Stripe Reader M2 for processing payments.
- **Admin Backend:** A service managing inventory, generating printable barcodes (formatted for Avery labels), and tracking sales analytics.
- **Payments Backend:** A robust API built with Rust on Cloudflare Workers, handling transactions, interacting with the Stripe API, and logging data for analytics.

## System Architecture

### 1. iPad App (Swift / iOS)

The toddler-facing POS interface on the iPad.

- **UI/UX:** Minimal text, large buttons, bright colors, and celebratory animations upon successful checkout.
- **Hardware Integration:**
  - **Barcode Scanner:** Tera Mini 1D 2D QR Wireless Barcode Scanner connected via Bluetooth (Keyboard Wedge Mode).
  - **Payment Terminal:** Stripe Reader M2 connected via Bluetooth, processed using the Stripe Terminal iOS SDK.
- **Authentication:** Uses Apple App Attest and generated API keys to securely communicate with the backend.

### 2. Backend API (Rust on Cloudflare Workers)

A single monolithic Cloudflare Worker handling both POS requests and Admin operations.

- **Payments:** Manages Stripe connection tokens, creates `PaymentIntents`, and captures authorized payments using server-to-server HTTP calls to the Stripe API.
- **Data Stores:**
  - **Cloudflare KV:** Stores inventory metadata keyed by barcode for ultra-fast edge retrieval.
  - **Cloudflare D1:** A relational SQLite database used to securely store transaction logs and history for analytics.

### 3. Admin System

The backend powers an admin interface (hosted on fintechnick.com) that enables:

- **Inventory Management:** Uploading photos, setting integer prices (e.g., $1, $5), and generating unique barcodes.
- **Barcode Printing:** Custom browser-side CSS for printing standard 1" x 2-5/8" Avery address labels.
- **Analytics:** Viewing a log of past transactions and sales data.

## Infrastructure & Tooling

This repository is configured with various tools to maintain code quality, security, and smooth CI/CD pipelines:

- DevContainers (Rust)
- CircleCI
- Doppler (Secrets Management)
- Cloudflare Wrangler
- Dependabot
- GitGuardian
- SonarCloud

## Development

The project is structured with comprehensive design documents and specifications located in the `specs/` directory, detailing API schemas, data architecture, sequence flows, and UI wireframes.

- **Rust Backend:** The Cloudflare worker source code and Cargo manifest are located in the `worker/` directory.
- **iOS App:** Source code for the iPad app is found in the `ios/` directory.
