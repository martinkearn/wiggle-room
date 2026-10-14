<!-- cloudkit-schema-deploy -->
## CloudKit schema changed: deploy to Production before TestFlight

This pull request changes `cloudkit/schema.ckdb`, so the app now syncs a field or record type that Production does not have yet. Until it is deployed, the TestFlight workflows fail at their schema check, and a TestFlight build would be rejected by CloudKit when it uploads.

Nothing in CI can do this for you. Follow these steps in order:

1. **Add the field to Development.** Run a development-signed build from this branch (Xcode, Run on a device or simulator signed in to iCloud) and add or edit one update, so a record containing the new field is saved. Alternatively, add the field by hand in [CloudKit Console](https://icloud.developer.apple.com/dashboard/) → your container → **Development** → **Record Types**.
2. **Clean up Development.** In the same Record Types view, delete any experimental fields or record types you don't want in Production. The deploy in step 5 pushes everything Development contains, and fields can never be removed from Production.
3. **Export the real schema.** Run this from the repository root, or use CloudKit Console → Development → **Export Schema…**:
   ```
   xcrun cktool export-schema --environment development --output-file cloudkit/schema.ckdb
   ```
   Check that the diff only adds the field this PR introduces. If the file still has a stand-in field type, this replaces it with the real one.
4. **Commit and push** the updated `cloudkit/schema.ckdb` to this branch.
5. **Deploy to Production.** In CloudKit Console, choose **Deploy Schema Changes…** (top left, next to the environment picker), review the list of changes, and confirm. Check that the list matches what this PR adds.
6. **Merge.** If you merge before step 5, both TestFlight workflows fail at **Check CloudKit Production schema**. Deploy, then re-run the failed jobs.

This comment updates itself when the PR changes and disappears if the PR stops changing the schema file.
