//
//  PaymentManager.swift
//
//  Created by Macgenics on 25/07/2025.
//

import StoreKit

public typealias Transaction = StoreKit.Transaction
public typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
public typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

public struct PaymentKeys {
    public let isPaidUser: String
    public let isLifeTimeSubscribed: String
    public let subscribedProductID: String

    public init(isPaidUser: String,
                isLifeTimeSubscribed: String,
                subscribedProductID: String) {
        self.isPaidUser = isPaidUser
        self.isLifeTimeSubscribed = isLifeTimeSubscribed
        self.subscribedProductID = subscribedProductID
    }
}



public enum StoreError: Error {
    case failedVerification
}

public extension Notification.Name {
    static let SubscriptionStatus = Notification.Name("IAPHelperPurchaseNotification")
    static let PurchaseFailedNotification = Notification.Name("IAPHelperFailNotification")
    static let PurchaseErrorNotification = Notification.Name("IAHelperERRORNotification")
    static let PurchaseExpiredNotification = Notification.Name("IAHelperExpireNotification")
    static let IAHelperHideHUD = Notification.Name("IAHelperHideHUD")
    static let NotPurchaseNotification = Notification.Name("IAHelperNotPurchaseNotification")
    static let PurchaseCancelErrorNotification = Notification.Name("IAHelperCancelErrorNotification")
}


public class Store: ObservableObject {
    
    private(set) var subscriptions: [Product]
    private(set) var nonConsume: [Product]
    private(set) var purchasedSubscriptions: [Product] = []
  
    private let keys: PaymentKeys
    
    public var productsList : [Product] = []
    
    public var productIDs: [String] = []
    
    var updateListenerTask: Task<Void, Error>? = nil
    
    public var introOfferEligibility: [String: Bool] = [:]
    
    public init(productIDs: [String], keys:PaymentKeys) {
        self.productIDs = productIDs
        subscriptions = []
        nonConsume = []
        self.keys = keys
        updateListenerTask = listenForTransactions()
        
        Task {
            await updateCustomerProductStatus()
        }
    }
    
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            //Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    //Deliver products to the user.
                    await self.updateCustomerProductStatus()
                    
                    //Always finish a transaction.
                    await transaction.finish()
                } catch {
                    //StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }
    public func requestProducts() async {
        do {
            //Request products from the App Store using the identifiers that the Products.plist file defines.
            let storeProducts = try await Product.products(for: productIDs)
            for product in storeProducts {
                print(product.id)
            }
            if let weeklyProduct = storeProducts.filter({$0.id.contains("week")}).first{
                productsList.append(weeklyProduct)
            }
            if let monthlyProduct = storeProducts.filter({$0.id.contains("month")}).first{
                productsList.append(monthlyProduct)
            }
            
            if let yearlyProduct = storeProducts.filter({$0.id.contains("yearly")}).first{
                productsList.append(yearlyProduct)
            }
            
            if let lifeProduct = storeProducts.filter({$0.id.contains("life")}).first{
                productsList.append(lifeProduct)
            }
            
            introOfferEligibility = [:]
            
            for product in productsList {
                if product.subscription?.introductoryOffer == nil {
                    introOfferEligibility[product.id] = false
                }else{
                    let isEligible = await checkIntroOfferEligibility(for: product)
                    introOfferEligibility[product.id] = isEligible
                }
            }
            
        } catch {
            print("Failed product request from the App Store server: \(error)")
        }
    }
    
    public func checkIntroOfferEligibility(for product: Product) async -> Bool {
        guard let subscriptionInfo = product.subscription else {
            return false
        }
        let eligibility =  await subscriptionInfo.isEligibleForIntroOffer
        return eligibility
    }
    
    @discardableResult
    public func purchase(_ product: Product) async throws -> Transaction? {
        //Begin purchasing the `Product` the user selects.
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            //Check whether the transaction is verified. If it isn't,
            //this function rethrows the verification error.
            let transaction = try checkVerified(verification)
            
            //The transaction is verified. Deliver content to the user.
            await updateCustomerProductStatus()
            
            //Always finish a transaction.
            await transaction.finish()
            
            return transaction
        case .userCancelled:
            let userInfo: [String: Any] = [NSLocalizedDescriptionKey: "Cancel Subscription"]
            purchaseExpired(userInfo: userInfo)
            return nil
        case .pending:
            return nil
        default:
            return nil
        }
    }
    
    func isPurchased(_ product: Product) async throws -> Bool {
        //Determine whether the user purchases a given product.
        switch product.type {
        case .nonRenewable:
            return false
        case .nonConsumable:
            return nonConsume.contains(product)
        case .autoRenewable:
            return purchasedSubscriptions.contains(product)
        default:
            return false
        }
    }
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        //Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            //StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case .verified(let safe):
            //The result is verified. Return the unwrapped value.
            return safe
        }
    }
    
    func updateCustomerProductStatus() async {
        var lifeTimePurchase: [String] = []
        var purchasedSubscriptions: [String] = []
        
        //Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            do {
                //Check whether the transaction is verified. If it isn’t, catch `failedVerification` error.
                let transaction = try checkVerified(result)
                //Check the `productType` of the transaction and get the corresponding product from the store.
                switch transaction.productType {
                case .nonConsumable:
                    if let car = productIDs.first(where: { $0 == transaction.productID }) {
                        lifeTimePurchase.append(car)
                    }
                case .nonRenewable:
                    break
                case .autoRenewable:
                    if let subscription = productIDs.first(where: { $0 == transaction.productID }) {
                        purchasedSubscriptions.append(subscription)
                    }
                default:
                    break
                }
            } catch {
                print()
            }
        }
        if lifeTimePurchase.isEmpty && purchasedSubscriptions.isEmpty{
            purchaseExpired()
            setLifetimePro(status: false)
            UserDefaults.standard.set("", forKey: "SubscribedID")
           // NotificationManager().removeSpecificNotification(identifier: "ShowPremiumPopup")
        }else if !purchasedSubscriptions.isEmpty{
            enablePro()
            setLifetimePro(status: false)
            UserDefaults.standard.set(purchasedSubscriptions.first, forKey: "SubscribedID")
            if let _ = purchasedSubscriptions.first(where: { !$0.contains("week")}) {
                UserDefaults.standard.set("", forKey: "SubscribedID")
             //   NotificationManager().removeSpecificNotification(identifier: "ShowPremiumPopup")
            }
        }else if !lifeTimePurchase.isEmpty{
            setLifetimePro(status: true)
            UserDefaults.standard.set("", forKey: "SubscribedID")
        }else{
            purchaseExpired()
            UserDefaults.standard.set("", forKey: "SubscribedID")
        }
    }
    func sortByPrice(_ products: [Product]) -> [Product] {
        products.sorted(by: { return $0.price < $1.price })
    }
    public func restorePurchases() async {
        do{
            try await AppStore.sync()
            SKPaymentQueue.default().restoreCompletedTransactions()
            await updateCustomerProductStatus()
        }catch {
            setLifetimePro(status: false)
            purchaseExpired()
        }
    }
    private func enablePro() {
        DispatchQueue.main.async {
            UserDefaults.standard.isPaidUser = true
            NotificationCenter.default.post(name: .SubscriptionStatus, object: nil)
        }
    }

    private func purchaseExpired(userInfo: [String: Any]? = nil) {
        UserDefaults.standard.isPaidUser = false
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .SubscriptionStatus, object: userInfo)
        }
    }

    private func setLifetimePro(status: Bool) {
        UserDefaults.standard.isLifeTimeSubscribed = status
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .SubscriptionStatus, object: nil)
        }
    }

}

public extension UserDefaults {
    
    public var isPaidUser: Bool {
        get { bool(forKey: PaymentKeys.isPaidUser) }
        set { set(newValue, forKey: PaymentKeys.isPaidUser) }
    }
    
    public var isLifeTimeSubscribed: Bool {
        get { bool(forKey: PaymentKeys.isLifeTimeSubscribed) }
        set { set(newValue, forKey: PaymentKeys.isLifeTimeSubscribed) }
    }
    
    public var subscribedProductID: String {
        get { string(forKey: PaymentKeys.subscribedProductID) ?? "" }
        set { set(newValue, forKey: PaymentKeys.subscribedProductID) }
    }
}


///How to set the keys from the app

//let keys = PaymentKeys(
//    isPaidUser: "myApp_isPaidUser",
//    isLifeTimeSubscribed: "myApp_isLifeTimeSubscribed",
//    subscribedProductID: "myApp_subscribedID"
//)

///how to check The subscription status

// UserDefaults.standerd.isPaidUser

///how to check The lifeTime status

// UserDefaults.standerd.isLifeTimeSubscribed




//how to use this manager

//create this in your basevc

//var paymentManager:Store!

//in didload

//paymentManager = .init()

//how to buy

//@objc func buyProductPress() {
//    if InternetManager.shared.isInternetConnected() {
//
//        self.buyBtn.animationButtonPressed()
//        self.hud.showHUD(on: view)
//        Task{
//            if let currentSelectedProduct{
//                try await appDelegate.paymentManager.purchase(currentSelectedProduct)
//            }
//        }
//    }else{
//        Utility.showNoInternetMessage(self)
//    }
//}


//@IBAction func restoreBtnPressed(_ sender: UIButton) {
//    if InternetManager.shared.isInternetConnected() {
//        self.hud.showHUD(on: view)
//        Utility.firebaseLogEvent(eventName: "Restore_Tapped_PremiumVCExperiment")
//        Task{
//            await self.paymentManager.restorePurchases()
//        }
//    }else{
//        Utility.showNoInternetMessage(self)
//    }
//}

//
//@objc func retriveProducts() -> Void{
//    if self.paymentManager.productsList.isEmpty{
//        self.hud.showHUD(on: self.view)
//        Task{
//            await self.paymentManager.requestProducts()
//            self.hud.hideHUD()
//            if self.paymentManager.productsList.isEmpty{
//                currentSelectedProduct = nil
//            }else{
//                let product = self.getProduct(productID: productsPlan[selectedIndex])
//                self.currentSelectedProduct = product
//            }
//            self.collectionView.reloadData()
//        }
//        collectionView.reloadData()
//    }else{
//        if self.paymentManager.productsList.isEmpty{
//            currentSelectedProduct = nil
//        }else{
//            let product = self.getProduct(productID: productsPlan[selectedIndex])
//            self.currentSelectedProduct = product
//        }
//        self.collectionView.reloadData()
//    }
//}

//Add this into baseVC

//
//func getProduct(productID:String) ->Product?{
//    if !self.paymentManager.productsList.isEmpty{
//        let product = self.paymentManager.productsList.first { product in
//            return product.id == productID
//        }
//        return product
//    }else{
//        return nil
//    }
//}

//add this observer
//NotificationCenter.default.addObserver(self, selector: #selector(self.updatePaymentStatus), name: Notification.Name.init(Store.SubscriptionStatus), object: nil)

//@objc func updatePaymentStatus(){
//    self.hud.hideHUD()
//    if Utility.checkAllPurchase(){
//        dismiss your VC
//    }
//}

