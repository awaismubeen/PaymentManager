//
//  PaymentManager.swift
//
//  Created by Macgenics on 25/07/2025.
//

import StoreKit

typealias Transaction = StoreKit.Transaction
typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

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
  
    
    var productsList : [Product] = []
    
    var productIDs: [String] = []
    
    var updateListenerTask: Task<Void, Error>? = nil
    var introOfferEligibility: [String: Bool] = [:]
    
    public init(productIDs: [String]) {
        self.productIDs = productIDs
        subscriptions = []
        nonConsume = []
        
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
    func requestProducts() async {
        do {
            //Request products from the App Store using the identifiers that the Products.plist file defines.
            let storeProducts = try await Product.products(for: productIDs)
            for product in storeProducts {
                print(product.id)
            }
            if let weeklyProduct = storeProducts.filter({$0.id.contains("month")}).first{
                productsList.append(weeklyProduct)
            }
            if let monthlyProduct = storeProducts.filter({$0.id.contains("life")}).first{
                productsList.append(monthlyProduct)
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
    func checkIntroOfferEligibility(for product: Product) async -> Bool {
        guard let subscriptionInfo = product.subscription else {
            return false
        }
        let eligibility =  await subscriptionInfo.isEligibleForIntroOffer
        return eligibility
    }
    
    @discardableResult func purchase(_ product: Product) async throws -> Transaction? {
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
    func restorePurchases() async {
        do{
            try await AppStore.sync()
            SKPaymentQueue.default().restoreCompletedTransactions()
            await updateCustomerProductStatus()
        }catch {
            setLifetimePro(status: false)
            purchaseExpired()
        }
    }
    private func enablePro(){
        DispatchQueue.main.async {
            UserDefaults.standard.set(true, forKey: "isPaidUser")
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: .SubscriptionStatus, object: nil)
        }
    }
    private func purchaseExpired(userInfo: [String: Any]? = nil){
        UserDefaults.standard.set(false, forKey: "isPaidUser")
        UserDefaults.standard.synchronize()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .SubscriptionStatus, object: userInfo)
        }
    }
    private func setLifetimePro(status:Bool){
        UserDefaults.standard.set(status, forKey: "isLifeTimeSubscribed")
        UserDefaults.standard.synchronize()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .SubscriptionStatus, object: nil)
        }
    }
}


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

