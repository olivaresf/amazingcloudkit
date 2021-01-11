//
//  AmazingUser.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 11/05/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class AmazingUser {
	
	/// Read and write access.
	public let ownDatabase: AuthenticatedUserDatabase
	
	/// Inviting via public records requires write access, so it belongs here.
	public let inviteService: InviteService
	
	public let recordID: CKRecord.ID
	
	/// You only get access to a friends database if a user has invited you to read/write a record via a CKShare.
	/// Note that inviting users to view one of your own records will not result in a populated `friendsDatabase`, as that record exists in `ownDatabase`.
	///
	/// In order to initialize this variable, call `resolveSharedDatabase`.
	public private(set) var friendsDatabase: FriendsDatabase? = nil
	
	/// Requests all zones in the friends database.
	///
	/// If any zones are returned, `self.friendsDatabase` will become non-nil and returned via the completion block.
	/// If no zones are returned, `self.friendsDatabase` will become nil.
	/// If there was an error fetching zones, it will be returned via the completion block.
	///
	/// - Parameter completion: self-explanatory
	public func resolveFriendsDatabase(completion: @escaping (Result<FriendsDatabase, ResolveFriendsDatabaseError>) -> Void) {
		
		friendsZoneFetcher.fetch { result in
			switch result {
				
			case .success(let resolvedZones):
				
				guard !resolvedZones.isEmpty else {
					self.friendsDatabase = nil
					completion(.failure(.emptyDatabase))
					return
				}
				
				self.friendsDatabase = FriendsDatabase(container: self.container,
													   customZones: resolvedZones)
				completion(.success(self.friendsDatabase!))
				
			case .failure(let error):
				self.friendsDatabase = nil
				completion(.failure(.other(error)))
			}
		}
	}
	
	private let container: CKContainer
	private let friendsZoneFetcher: CustomZoneFetcher
	
	init(container: CKContainer, recordID: CKRecord.ID) {
		self.container = container
		ownDatabase = AuthenticatedUserDatabase(container: container)
		friendsZoneFetcher = CustomZoneFetcher(database: container.sharedCloudDatabase)
		inviteService = InviteService(container: container)
		self.recordID = recordID
	}
}

extension AmazingUser {
	public enum ResolveFriendsDatabaseError : Error {
		case emptyDatabase
		case other(Error)
	}
}
