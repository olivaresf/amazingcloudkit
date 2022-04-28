# AmazingCloudkit

CloudKit isn't as straightforward as a lot of Apple frameworks. There are many small caveats and details that are counterintuitive until you read a lot of documentation or try it out yourself. AmazingCloutkit is the result of all the lessons I learned while implementing Cloudkit.

## The Facts

The hierarchy of objects in CloudKit goes something like this:

Containers:
- subclasses of `CKContainer`
- exist for every app (if you have multiple apps, you have multiple containers)
- handle user authorization (i.e. requesting the user allow the app CloudKit access)
- handle user authentication (i.e. authenticating the user has a CloudKit account)
- is in charge of sharing individual records

Databases:
- subclasses of `CKDatabasse`
- Each container holds 3 different types of databases: public, shared and private.
- All 3 databases are always available to the container, regardless if the user is logged into iCloud or if they have write access. 
- Each database holds zones, which you can think of as a logical grouping of records.
- Finally, each zone holds records.

Records:
- You can fetch records using their Record.ID (a meta object) or the record ID itself (the identifier)

All of this sounds straightforward until...

## The issues

The issues here should all be trivial tasks and yet...

Alice wants a list of all her personal and shared records (e.g. a list of her own notes)

0. Make sure custom zones in the private database are created, otherwise all records will be saved to the user's default zone and will not be eligible for sharing.
0. If no custom zones found in the private databse, create one now.
1. Fetch all zones from the private database.
2. Fetch all records of the defined type.
3. Fetch all zones from the shared database.
4. Fetch all records of the defined type.
5. Merge all results into a single array.

Alice wants to share a record with Bob

0. Create the record to be shared. This record must exist in the private database and in a custom zone.
0a. If you do not have a custom zone, you must create it first.
0b. If you created the record in the default zone, you must move the record to the custom zone first.
1. Create a CKShare object.
2. Attach that CKShare object to a CKRecord.
3. Save both the CKShare and the CKRecord at the same time.
4. Open a UICloudSharingController so the user manually chooses with whom to share the record.
5. Have the other person accept the CKShare.

Bob wants to see the record Alice shared with him.

0. Define the record type you want to fetch (e.g. of type "Note")
1. Fetch all zones from the shared database.
2. Fetch all records of the defined type.
3. Filter from all the records to find the record Bob wants to see.
4. Transform the CKRecord to your object of choice.

Bob wants to get notifications whenever a record changes.

0. Create a CKSubscription object.
0. Get the record's owning database.
1. Post the subscription to CloudKit via the database.
2. Fetch all subscriptions to make sure you didn't post the same subscription twice otherwise Bob gets 2 notifications every time the subscription is triggered.

Alice has selected a record and wants to modify it (e.g. upload a photo to a note she has access to)

1. Find out what database the record belongs to.
1.1y If your object contains a custom field "Database", go to step 2.
1.1n If not, fetch all record types (with their IDs only) from all zones the private database and compare it to the original record. If you find a match, it's the private database.
1.2n If you did not find a match in the private database, fetch all record types from all zones in the shared database and compare it to the original record. If you find a match, it's the shared database.
1.3n If you did not find a match, this is a local record that you kept, so you're not modifying, you're uploading.
2. Since this is a modification, make sure the record has a RecordID with the custom zone it's going to.
3. Save the record

Smaller, but annoying issues:
- Welcome to closure hell.
- Databases are _always_ available, so you can execute queries against them. Meaning, if the user is logged out, they can still attempt to write to their private database which will fail.
- The public database is available read-only always but write access is only enabled for logged users.
- You cannot create custom zones in the public database.
- The private database is queriable only by logged users. You can still send requests to it, just know they will all fail.
- The private database has a default zone, but records in it cannot be shared.
- The shared database is queriable only by logged users.
- The shared database doesn't have a default zone, only custom zones.
- You cannot create zones in the shared database directly. The zones are created when sharing.
- If you share a record with someone else, that record will never appear in the shared database. It will always be in the private database.
- Finding a record in a database requires one fetch per zone, since you cannot fetch records from the database. 
- When fetching objects from multiple zones, it's possible that one zone fails, so you have valid results and an error.
- You can easily duplicate subscriptions, sending one notification per subscription for the same event.

## The Fix

I haven't been able to solve all of these issues, but I've attempted to fix many of them. 

### Compiler help.
For example, AmazingCloudKit will always have a constant to the public database (henceforth known as the `AllAppUsersDatabase`) and this object will always have the ability to read records, but will have an optional when it comes to writing records.

```
public class AllAppUsersDatabase {
	
	/// All users of your app, regardless of authentication state, may read from this database.
	public let read: ReadableZone
	
	/// Only authenticated users may write.
	/// In order to initialize this service, call AmazingCloudkit's `resolveUser`.
	public internal(set) var write: WritableZone?

  ...
}
```

### Fetching all shared records
Another common scenario I faced was getting all records of a certain type shared _with_ the user. That process, as outlined above, is annoying and error prone. You can now do something like this:

```
let friendsDatabase = AmazingCloudKit.authenticatedUser?.friendsDatabase!

friendsDatabase.fetch { (result: Result<[Result<[CustomCKConvertibleObject], Error>], ReadableZone.ResolveCustomZonesError>) in
    switch result {
    
    case .success(let resultsByZone):
        // Each zone had a request sent to fetch all records of type CustomCKConvertibleObject.
        for zoneResult in resultsByZone {
            // If the zone brought back records, .success([CustomCKConvertibleObject])
            // If the zone failed, .failure(Error)
        }
        
    case .failure(let noZonesFound):
        // No zones found in the friends database. No records have been shared with this user.
    }
}
```

Also, as you can see, the elements can be transformed from and to a CKRecord via a custom protocol called CKRecordConvertible.

## Quick Start

Create an amazing CloudKit. If you only want to read the public databse, you're good to go.

```
let amazingCloudKit = AmazingCloudKit()
amazingCloudKit.allUsersDatabase.read.fetch { (result: Result<[MyCustomObject: CKRecordDecodable & CKRecordIdentifiable], Error>) in
			
    switch result {
    case .success(let fetchedMyCustomObjects):
    break
				
    case .failure(let error):
    break
    }
}
```

If you want to get write access, you must first ask the user for consent via `requestApplicationPermission`, then you may call `resolveUser`.

```
let amazingCloudKit = AmazingCloudKit()

// You have already requested and been granted access.
self.amazingCloudKit.resolveUser { result in
    switch result {
    case .success(let loggedUser):
        // Now that you have a logged user, save a reference to it as you will need it if you want to read/write the private database or the friends database.
        // e.g. loggedUser.ownDatabase.write.save(record)
        // or
        // loggedUser.friendsDatabase.resolve { }
        
    case .failure(let error):
    break
    }
}

```

## Pending Work

There's a lot of pending work. I spent a few months trying to have fun with CloudKit but you'll notice this is incomplete in many ways. It's missing a wrapper around `requestApplicationPermission`, it can't go beyond the basic query limit (e.g. fetching more than 200 objects or so), and it needs an example project.

However, I'm publishing it in hopes that it's useful to someone. This project proved to be very useful for me to get an app off the ground. I hope it helps you!
