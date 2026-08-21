# Chart rendering tests

`render-golden.sh` renders focused value combinations and compares them with
the manifests under `golden/`. Run it after `helm lint` for normal verification:

```sh
tests/render-golden.sh
```

When an intentional template change alters output, inspect the diff and then
regenerate the snapshots explicitly:

```sh
UPDATE_GOLDEN=1 tests/render-golden.sh
```

The `custom-driver`, `release-namespace`, and `explicit-false` cases also make
semantic assertions for value wiring that must not regress. Namespace checks
cover both the Helm release namespace and an explicit chart override. Chart and
app versions are normalized so release-only version bumps do not churn the
snapshots.
