//
//  AmazingCloudKit.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 15/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class AmazingCloudKit {
	
	/// You always have access to the public database, regardless of authentication state.
	/// However, write access is only enabled after resolving a user (i.e. authenticating a user).
	public let allUsersDatabase: AllAppUsersDatabase
	
	/// An authenticated user gets
	/// - write access to the public database
	/// - read/write to their private database
	/// - if someone shared records with them, to the shared database.
	///
	/// To initalize this variable, call `resolveUser.`
	public private(set) var authenticatedUser: AmazingUser? = nil
	
	public let discoveryService: DiscoveryService
	
	public init(container: CKContainer = CKContainer.default()) {
		self.container = container
		allUsersDatabase = AllAppUsersDatabase(container: container)
		discoveryService = DiscoveryService(container: container)
		
		// As per the docs, "While your app is running, use the CKAccountChanged notification to detect account changes [...]"
		NotificationCenter.default.addObserver(self,
											   selector: #selector(accountStatusChanged(notification:)),
											   name: .CKAccountChanged,
											   object: nil)
	}
	
	/// In order to get write access to the public database, read/write access to the private and shared databases, we need to know if the user is logged in.
	///
	/// - Parameter completion: if authenticated, a new user with a private database
	public func resolveUser(completion: @escaping (Result<AmazingUser, ResolvedUserError>) -> Void) {
		
		container.accountStatus { status, possibleError in
			
			guard possibleError == nil else {
				completion(.failure(.other(possibleError!)))
				return
			}
			
			let resolutionError: ResolvedUserError
			switch status {
				
			case .available:
				
				self.discoveryService.fetchRecordIDForLoggedUser { result in
					switch result {
					case .success(let possibleID):
						
						guard let userIdentifier = possibleID else {
							completion(.failure(.identifierNotFound))
							return
						}
						
						let loggedUser = AmazingUser(container: self.container,
													 recordID: userIdentifier)
						self.authenticatedUser = loggedUser
						
						self.allUsersDatabase.write = WritableZone(database: self.container.publicCloudDatabase,
																   zoneID: CKRecordZone.ID.default)
						
						completion(.success(loggedUser))
						
					case .failure(let discoveryError):
						completion(.failure(.identifierFetchFailed(discoveryError)))
					}
				}
				return
				
			case .couldNotDetermine:
				resolutionError = .couldNotDetermine
				
			case .noAccount:
				resolutionError = .noAccount
				
			case .restricted:
				resolutionError = .restricted
				
			@unknown default:
				resolutionError = .couldNotDetermine
			}
			
			self.authenticatedUser = nil
			self.allUsersDatabase.write = nil
			completion(.failure(resolutionError))
		}
	}
	
	private let container: CKContainer
}

extension AmazingCloudKit {
	
	public enum ResolvedUserError : Error {
		case couldNotDetermine
		case noAccount
		case restricted
		case identifierNotFound
		case identifierFetchFailed(Error)
		case other(Error)
	}
	
	// Used by both ReadableZone and FetchError
	public enum FetchError : Error {
		case cloudKit(Error)
		case invalidStateNoErrorButNoRecords
	}
	
	@objc private func accountStatusChanged(notification: Notification) {
		resolveUser { _ in }
	}
}

public typealias ZoneName = String
