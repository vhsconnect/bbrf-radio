# To do

## Hub and ingest

- [ ] **`GET /sync` on the hub**: when the last sync arrived, from which node, and how much history the hub holds (oldest and newest observation, row count).
- [ ] **Send only the changed stations**: today every sync sends the whole stations table (about 56 MB, 70k rows). Send only the ones changed since the last sync (`last_changed_at`) if that ever matters.
- [ ] **`make attach` on a split node**: it uses `--sname`, so it only reaches an `all` node. The ingest node would need its TLS option file and cookie; the hub accepts no certificate but the ingest node's, by design.
