# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# First-boot self-seed: a fresh self-hosted instance has no Scryfall card data yet.
# Enqueue the sync instead of running it inline so `db:seed`/deploy doesn't block on a
# multi-MB download; the recurring job (config/recurring.yml) keeps it fresh after that.
# Idempotent — the production entrypoint runs this on every boot.
ScryfallSyncJob.enqueue_unless_catalog_ready
