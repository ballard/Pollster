//
//  AllQandAsTableViewController.swift
//  Pollster
//
//  Created by Ivan on 04.11.16.
//  Copyright © 2016 Ivan. All rights reserved.
//

import UIKit
import CloudKit

class AllQandAsTableViewController: UITableViewController {

    var allQandAs = [CKRecord]() {
        didSet {
            tableView.reloadData()
        }
    }
    
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return allQandAs[indexPath.row].wasCreatedByThisUser
    }
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            let record = allQandAs[indexPath.row]
            database.deleteRecordWithID(record.recordID) { (record, error) in
                // handle erorrs
            }
            allQandAs.removeAtIndex(indexPath.row)
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        fetchAllQandAs()
        iCloudSubscribeToQandAs()
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        iCloudUnsubscribeToQandAs()
    }
    
    private let database = CKContainer.defaultContainer().publicCloudDatabase
    private func fetchAllQandAs() {
        let predicate = NSPredicate(format: "TRUEPREDICATE")
        let query = CKQuery(recordType: Cloud.Entity.QandA, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Cloud.Attribute.Question, ascending: true)]
        database.performQuery(query, inZoneWithID: nil) { (records, error) in
            if records != nil {
                dispatch_async(dispatch_get_main_queue()) {
                    self.allQandAs = records!
                }
            }
        }
    }
    
    private let subscriptionID = "All QandAs Creations and Deletions"
    private var cloudKitObserver: NSObjectProtocol?
    
    private func iCloudSubscribeToQandAs () {
        let predicate = NSPredicate(format: "TRUEPREDICATE")
        let subcription = CKQuerySubscription(
            recordType: Cloud.Entity.QandA,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.FiresOnRecordCreation, .FiresOnRecordDeletion]
        )
//        subcription.notificationInfo = ... // possible to set
        database.saveSubscription(subcription) { (subscription, error) in
            if error?.code == CKErrorCode.ServerRejectedRequest.rawValue {
                // ignore record already created
            } else if error != nil {
                // report
            }
        }
        cloudKitObserver = NSNotificationCenter.defaultCenter().addObserverForName(
            CloudKitNotifications.NotificationReceived,
            object: nil,
            queue: NSOperationQueue.mainQueue(),
            usingBlock: { (notification) in
                if let ckqn = notification.userInfo?[CloudKitNotifications.NotificationKey] as? CKQueryNotification {
                    self.iCloudHandleSubscriptionNotifications(ckqn)
                }
            }
        )
    }
    
    private func iCloudHandleSubscriptionNotifications(ckqn: CKQueryNotification) {
        if ckqn.subscriptionID == self.subscriptionID {
            if let recordId = ckqn.recordID {
                switch ckqn.queryNotificationReason {
                case .RecordCreated:
                    database.fetchRecordWithID(recordId) { (record, error) in
                        if record != nil {
                            dispatch_async(dispatch_get_main_queue()) {
                                self.allQandAs = (self.allQandAs + [record!]).sort{
                                    return ($0.question < $1.question)
                                }
                            }
                        }
                    }
                case .RecordDeleted:
                    dispatch_async(dispatch_get_main_queue()) {
                        self.allQandAs = self.allQandAs.filter({ $0.recordID != recordId })
                    }
                default:
                    break
                }
            }
        }
    }
    
    private func iCloudUnsubscribeToQandAs () {
        database.deleteSubscriptionWithID(subscriptionID) { (subscription, error) in
            //
        }
        if cloudKitObserver != nil {
            NSNotificationCenter.defaultCenter().removeObserver(cloudKitObserver!)
        }
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allQandAs.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Show QandA", forIndexPath: indexPath)
        cell.textLabel?.text = allQandAs[indexPath.row].question as? String
        return cell
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "Show QandA" {
            if let ckQandATVC = segue.destinationViewController as? CloudQandATableViewController {
                if let cell = sender as? UITableViewCell, let indexPath = tableView.indexPathForCell(cell) {
                    ckQandATVC.ckQandARecord = allQandAs[indexPath.row]
                } else {
                    ckQandATVC.ckQandARecord = CKRecord(recordType: Cloud.Entity.QandA)
                }
            }
        }
    }
}
