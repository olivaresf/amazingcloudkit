//
//  CKDiscoveryCoordinator.swift
//  Amazing Humans
//
//  Created by Fernando Olivares on 12/17/19.
//  Copyright © 2019 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class CKSerialDiscoveryCoordinator {
	
	public enum UserDecision {
		case granted
		case denied
		case unknown
		
		var boolValue: Bool {
			switch self {
			case .granted: return true
			case .denied, .unknown: return false
			}
		}
	}
	
	let container: CKContainer
	public init(container: CKContainer) {
		self.container = container
	}
	
	public enum UserDiscoverabilityError : Error, CustomStringConvertible {
		case ckContainer(Error)
		case unknown(Error)
		case invalidState
		
		public var description: String {
			switch self {
			case .ckContainer(let error): return error.localizedDescription
			case .unknown(let error): return error.localizedDescription
			case .invalidState: return "Invalid State"
			}
		}
	}
	
    public func discoverUser(email: String) throws -> CKUserIdentity? {
        
        return try await { (awaitCompletion: @escaping (Result<CKUserIdentity?, UserDiscoverabilityError>) -> Void) in
            
			self.container.discoverUserIdentity(withEmailAddress: email) { possibleIdentity, error in

                guard error == nil else {
                    awaitCompletion(.failure(.ckContainer(error!)))
                    return
                }

                awaitCompletion(.success(possibleIdentity))
            }
        }
    }
    
    public func fetchRecordIDForLoggedUser() throws -> CKRecord.ID?  {
		
		return try await { (awaitCompletion: @escaping (Result<CKRecord.ID?, UserDiscoverabilityError>) -> Void) in
            
			self.container.requestApplicationPermission(.userDiscoverability) { (status, error) in
                
                guard error == nil else {
                    awaitCompletion(.failure(.ckContainer(error!)))
                    return
                }
                
                guard status == .granted else {
                    awaitCompletion(.failure(.invalidState))
                    return
                }
                
                CKContainer.default().fetchUserRecordID { possibleIdentity, error in

                    guard error == nil else {
                        awaitCompletion(.failure(.ckContainer(error!)))
                        return
                    }

                    awaitCompletion(.success(possibleIdentity))
                }
            }
        }
    }
	
	func another() {
		let result = fetchRecordIDForLoggedUser_result()
		do {
			let result = try result.get()
		} catch error as UserDiscoverabilityError {
			
		} catch {
			
		}
	}
	
	public func fetchRecordIDForLoggedUser_result() -> Result<CKRecord.ID?, UserDiscoverabilityError>  {
		return await { (awaitCompletion: @escaping (Result<CKRecord.ID?, UserDiscoverabilityError>) -> Void) in
			
			self.container.requestApplicationPermission(.userDiscoverability) { (status, error) in
				
				guard error == nil else {
					awaitCompletion(.failure(.ckContainer(error!)))
					return
				}
				
				guard status == .granted else {
					awaitCompletion(.failure(.invalidState))
					return
				}
				
				CKContainer.default().fetchUserRecordID { possibleIdentity, error in
					
					guard error == nil else {
						awaitCompletion(.failure(.ckContainer(error!)))
						return
					}
					
					awaitCompletion(.success(possibleIdentity))
				}
			}
		}
    }
    
    public func fetchUserIdentity(from recordID: CKRecord.ID) throws -> CKUserIdentity {
        
        return try await { (awaitCompletion: @escaping (Result<CKUserIdentity, UserDiscoverabilityError>) -> Void) in
                
            CKContainer.default().discoverUserIdentity(withUserRecordID: recordID) { possibleUserIdentity, possibleError in
                
                guard possibleError == nil else {
                    awaitCompletion(.failure(.ckContainer(possibleError!)))
                    return
                }
                
                guard let userIdentity = possibleUserIdentity else {
                    awaitCompletion(.failure(.invalidState))
                    return
                }
                
                awaitCompletion(.success(userIdentity))
            }
        }
    }
	
	public func requestUserApprovalForUserDiscoverability() throws -> UserDecision {
		
		return try await(asyncExecutionBlock: { (awaitCompletion: @escaping (Result<UserDecision, UserDiscoverabilityError>) -> Void) in
			
			// The following switch is the perfect example as to why you should leverage enums when reporting a single result, instead of 2 variables for 1 result.
			self.container.requestApplicationPermission(.userDiscoverability) { status, possibleError in
				
				// We cannot check for an error here because the documentation is not specific as to whether the error is only reported when `status == couldNotComplete` or if it's also sent along with any other state.
				
				switch status {
					
				case .couldNotComplete:
					
					// Documentation says we should be receiving an error when `couldNotComplete` is returned.
					guard let error = possibleError else {
						awaitCompletion(.failure(.invalidState))
						return
					}
					
					awaitCompletion(.failure(.ckContainer(error)))
					
				case .initialState:
					
					assertionFailure("We literally just requested it. How come it's still in an initial state?")
					
					// Sanity check.
					guard possibleError == nil else {
						awaitCompletion(.failure(.unknown(possibleError!)))
						return
					}
					
					awaitCompletion(.failure(.invalidState))
					
				case .denied:
					
					// Sanity check.
					guard possibleError == nil else {
						awaitCompletion(.failure(.unknown(possibleError!)))
						return
					}
					
					awaitCompletion(.success(.denied))
					
				case .granted:
					
					// Sanity check.
					guard possibleError == nil else {
						awaitCompletion(.failure(.unknown(possibleError!)))
						return
					}
					
					awaitCompletion(.success(.granted))
					
				@unknown default:
					awaitCompletion(.failure(.invalidState))
				}
			}
		})
	}
}
