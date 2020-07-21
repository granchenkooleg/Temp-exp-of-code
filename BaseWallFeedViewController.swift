//
//  BaseWallFeedViewController.swift
//  Zonto
//
//  Created by Oleg Granchenko on 10/11/17.
//  Copyright © 2017 Oleg Granchenko. All rights reserved.
//

import UIKit
import ImageViewer
import GoogleMobileAds

private let xibCellName = "NewsFeedCell"

struct WallFeedConfigurator {
    let defaultPostTextLeaght: Int
    let showMoreButton: Bool
}

class BaseWallFeedViewController: UIViewController, WallAndFeedDelegate, UIGestureRecognizerDelegate, GADBannerViewDelegate, GADUnifiedNativeAdLoaderDelegate, ContentOffsetProtocol {
    
    // MARK: - Properties
    private var tempModelList = [GetPostResponse]()
    let aDNativeManager = GADUnifiedNativeAdManager.sharedManager
    private var indexAd: Int = 0
    private var indexNativeAdOutsideScreen: Int = 0
    private var collectionViewItems = [AnyObject]()
    private var adsToLoad = [GADBannerView]()
    private var tepmtNativeAds = [GADUnifiedNativeAd?]()
    private var loadStateForAds = [GADBannerView: Bool]()
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"
    // A banner ad is placed in the UITableView once per `adInterval`. iPads will have a
    // larger ad interval to avoid mutliple ads being on screen at the same time.
    private let adInterval = 0
    private var adIntervalNative = 0
    // The banner ad height.
    private let adViewHeight = CGFloat(100)
    
    @IBOutlet weak var collectionView: UICollectionView!
    var model: BaseSocketWallAndFeedModel!
    public var collectionRefreshControl = UIRefreshControl()
    public let dataSourceUpdater = FeedWallUpdater()
    public var headerLayotInfo = HeaderViewSize()
    
    public var showAdditionalFooter: Bool { return true }
    
    public var configurator: WallFeedConfigurator {
        return WallFeedConfigurator(defaultPostTextLeaght: 300, showMoreButton: true)
    }
    
    private var cellIdentifier:String  { return  "NewsFeedCell" }
    
    private lazy var tempCell: BaseFeedCell = {
        return createTempCell()
    }()
    
    lazy var headerView: BaseHeaderView = {
        let view = Bundle.main.loadNibNamed("BaseHeaderView", owner: self, options: nil)?.first as! BaseHeaderView
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private var topPlaceholderOffset: NSLayoutConstraint?
    private var placeholder: PlaceholderCell?
    
    private var heightSectionHeader: CGFloat {
        switch view.findViewController() {
        case let vc where vc is UserWallViewController || vc is GroupWallViewController:
            return FeedPostContainerView.heightReusableView + FeedSeparatorHeaderView.heightReusableView
        default:
            return 0
        }
    }
    
    private(set) lazy var wrapPlaceholder: UIView  = {
        let wrap = UIView()
        if let placeholderView = Bundle.main.loadNibNamed("PlaceholderCell", owner: nil, options: nil)?.first as? PlaceholderCell {
            self.placeholder = placeholderView
            wrap.addSubview(placeholderView)
            placeholderView.translatesAutoresizingMaskIntoConstraints = false
            placeholderView.leadingAnchor.constraint(equalTo: wrap.leadingAnchor).isActive = true
            placeholderView.trailingAnchor.constraint(equalTo: wrap.trailingAnchor).isActive = true
            placeholderView.bottomAnchor.constraint(equalTo: wrap.bottomAnchor).isActive = true
            topPlaceholderOffset = placeholderView.topAnchor.constraint(equalTo: wrap.topAnchor, constant: (headerLayotInfo.heightBaseHeader + heightSectionHeader)) // indent for clear corner radiuses
            topPlaceholderOffset?.isActive = true
            configurePlaceholder()
        }
        wrap.isUserInteractionEnabled = false
        return wrap
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setInitialAdInterval()
        let _ = wrapPlaceholder
        collectionRefreshControl.addTarget(self, action: #selector(self.refresh), for: UIControl.Event.valueChanged)
        collectionView?.addSubview(collectionRefreshControl)
        collectionView?.alwaysBounceVertical = true
        
        collectionView.dataSource = self
        collectionView.delegate = self
        
        let cellNib = UINib(nibName: xibCellName, bundle: nil)
        collectionView.register(cellNib, forCellWithReuseIdentifier: self.cellIdentifier)
        collectionView.register(UINib(nibName: "BannerAd", bundle: nil), forCellWithReuseIdentifier: "BannerViewCell")
        collectionView.register(UINib(nibName: "UnifiedNativeAdCell", bundle: nil), forCellWithReuseIdentifier: "UnifiedNativeAdCell")
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func updateContentInset(_ inset: UIEdgeInsets) {
        customContentOffset(with: inset, collectionView: collectionView)
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let yOffset = self.collectionView.contentOffset.y
        let topInset = collectionView.contentInset.top
        
        if yOffset < -topInset / 2 {
            self.collectionView.setContentOffset(CGPoint(x:0, y:-topInset), animated: true)
        }
        else if yOffset <= 0{
            self.collectionView.setContentOffset( .zero, animated: true)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        prepareAdNative()
        collectionRefreshControl.endRefreshing()
        model.delegate = self
        reloadCollection()
        updateViewPostTimerWithDelay()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.delegate = nil
        for cell in collectionView.visibleCells {
            if let feedCell = cell as? BaseFeedCell {
                feedCell.cancelDownload()
            }
        }
        tempCell.cancelDownload()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(sendVisiblePosts), object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    func removeCell(index: Int)
    {
        self.model.remove(element: collectionViewItems[index] as! GetPostResponse)
        reloadCollection()
    }
    
    func addHeaderView() {
        self.view.insertSubview(headerView, at: 0)
        self.headerView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor).isActive = true
        self.headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        self.headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        self.collectionView.contentInset = UIEdgeInsets(top: headerLayotInfo.heightBaseHeader, left: 0, bottom: 0, right: 0)
    }
    
    func createFotterItems(for post: GetPostResponse) -> [FeedCellFooterItem] {
        let isLiked = (post.liked ?? 0) == 1
        if let viewsCount = post.viewsCount {
            return [.likes(isLiked, post.likes_count), .coints(post.coins_count), .comments(post.commentsCount), .views(viewsCount)]
        }
        return [.likes(isLiked, post.likes_count), .coints(post.coins_count), .comments(post.commentsCount)]
    }
    
    fileprivate func indexOfModel(_ post: GetPostResponse) -> Int? {
        return model.postList.firstIndex(where: { return post.post_id == $0.post_id })
    }
    
    fileprivate func indexCVIts(_ post: GetPostResponse) -> Int? {
        return collectionViewItems.firstIndex(where: { return post.post_id == ($0 as? GetPostResponse)?.post_id })
    }
    
    func update(posts: [GetPostResponse]) {
        for post in posts {
            guard let _indexCVIts = indexCVIts(post), let _indexModel = indexOfModel(post) else { return }
            let indexPathModel = IndexPath(row: _indexModel, section: 0)
            let indexPath = IndexPath(row: _indexCVIts, section: 0)
            if let cell = collectionView.cellForItem(at: indexPath) as? BaseFeedCell {
                updatePost(cell: cell, at: indexPathModel)
            }
        }
    }
    
    fileprivate func getObjModel(_ indexPath: IndexPath, _ objectModel: inout GetPostResponse?, _ deque: Bool) {
        if indexPath.row < collectionViewItems.count {
            objectModel = deque ? (collectionViewItems[indexPath.row] as? GetPostResponse) : model.postList[indexPath.row]
        } else {
            objectModel = model.postList[indexPath.row] // This is for a detail cell
        }
    }
    
    private func updatePost(deque: Bool = false, cell: BaseFeedCell, at indexPath: IndexPath) {
        var objectModel: GetPostResponse? = nil
        getObjModel(indexPath, &objectModel, deque)
        
        cell.delegate = self
        if let postID = objectModel?.post_id,
            let info = dataSourceUpdater.sizeCache[postID] {
            cell.feedContentView.textLabel.maxLeaghtText = info.maxContentLeaght
        }
        guard let objModel = objectModel else { return }
        cell.loadPost(post: objModel, isShowFotter: showAdditionalFooter)
        cell.footerView.configureFootter(createFotterItems(for: objModel))
        cell.headerView.moreButton.isHidden = !configurator.showMoreButton
    }
    
    func shareDomaine(post: GetPostResponse) -> String? {
        return nil
    }
    
    func displayPlaceHolderIfNeed() {
        configurePlaceholder()
        if model.postList.count == 0 {
            collectionView.backgroundView = wrapPlaceholder
        }
        else {
            collectionView.backgroundView = nil
        }
    }
    
    func reloadCollection() {
        displayPlaceHolderIfNeed()
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        
        collectionView.performBatchUpdates({
            setModelObj()
            if self.numberOfSections(in: collectionView) == 1 {
                self.collectionView.reloadSections(IndexSet(integer: 0))
            } else {
                self.collectionView.reloadData()
            }
        }) { (_) in
        }
        updateViewPostTimerWithDelay()
    }
    
    func configurePlaceholder() {
        placeholder?.image.image = #imageLiteral(resourceName: "placeholder_empty_feeds")
        placeholder?.title.text = localized("feed_no_post_lable", defaultString: "Нет публикаций")
    }
    
    
    func placeholderCellSize(offset: CGFloat = 0) {
        topPlaceholderOffset?.constant = offset + heightSectionHeader //  heightSectionHeader is indent for clear corner radiuses
    }
    
    func updateViewPostTimerWithDelay() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(sendVisiblePosts), object: nil)
        let deelay: TimeInterval = TimeInterval(SettingManager.sharedInstance.serverSetting.value.viewPostInterval)
        self.perform(#selector(self.sendVisiblePosts), with: nil, afterDelay: deelay)
    }
    
    @objc func sendVisiblePosts() {
        if collectionViewItems.count > 0 {
            let visibleIndexs = collectionView.indexPathsForVisibleItems
            var visiblePostsID = [String]()
            for index in visibleIndexs {
                if collectionView.cellForItem(at: index) is BaseFeedCell,
                    let cvItem = collectionViewItems[index.row] as? GetPostResponse, let postID = cvItem.post_id {
                    visiblePostsID.append(postID)
                }
            }
            if visiblePostsID.count > 0 {
                model.updateVisible(posts: visiblePostsID)
            }
        }
    }
}

// MARK: - Google Ads
extension BaseWallFeedViewController {
    // MARK: - Ad generation
    fileprivate func setInitialAdInterval() {
        //           indexAd = SettingManager.sharedInstance.serverSetting.value....!!??
        adIntervalNative = SettingManager.sharedInstance.serverSetting.value.adsPostEvery
        indexNativeAdOutsideScreen = adIntervalNative
    }
    
    fileprivate func prepareAdNative() {
        if !(view.findViewController() is UserWallViewController), !(view.findViewController() is DetailPostViewController), !(view.findViewController() is HashTagFeedViewController) {
            guard aDNativeManager.adLoader == nil else { return }
            guard adIntervalNative > 0 else { return }
            aDNativeManager.prepareAdNativeToLoad(view: view)
        }
    }
    
    fileprivate func doBannerAds() {
        //            addBannerAds()
        //            preloadNextAd()
        
        addNativeAds()
    }
    
    fileprivate func increaseNativeAds() {
        if model.postList.count > tempModelList.count {
            let countPosts =  model.postList.count - tempModelList.count
            let countNeedAd = (countPosts / 4)
            guard countNeedAd <= aDNativeManager.numAdsToLoad else { return }
            for adv in 0..<countNeedAd {
                tepmtNativeAds.append(aDNativeManager.nativeAds[adv] ?? .none)
            }
        }
        // Absolve array
        aDNativeManager.nativeAds = aDNativeManager.nativeAds.suffix(aDNativeManager.numAdsToLoad)
    }
    
    fileprivate func setModelObj() {
        collectionViewItems = model.postList
        guard !aDNativeManager.nativeAds.isEmpty else { return }
        guard !(view.findViewController() is UserWallViewController), !(view.findViewController() is DetailPostViewController), !(view.findViewController() is HashTagFeedViewController) else { return }
        increaseNativeAds()
        tempModelList = model.postList
        doBannerAds()
    }
    
    // MARK: - GADBannerView delegate methods
    func adViewDidReceiveAd(_ adView: GADBannerView) {
        loadStateForAds[adView] = true
        preloadNextAd()
    }
    
    func adView(_ adView: GADBannerView, didFailToReceiveAdWithError error: GADRequestError) {
        print("Failed to receive ad: \(error.localizedDescription)")
        preloadNextAd()
    }
    
    // MARK: - UICollectionView Banner data generation
    private func addBannerAds() {
        // Ensure subview layout has been performed before accessing subview sizes.
        collectionView.layoutIfNeeded()
        while indexAd < collectionViewItems.count {
            let adSize = GADAdSizeFromCGSize(
                CGSize(width: collectionView.contentSize.width, height: adViewHeight))
            let adView = GADBannerView(adSize: adSize)
            adView.adUnitID = adUnitID
            adView.rootViewController = self
            adView.delegate = self
            
            collectionViewItems.insert(adView, at: indexAd)
            adsToLoad.append(adView)
            loadStateForAds[adView] = false
            
            indexAd += adInterval
        }
    }
    
    private func preloadNextAd() {
        if !adsToLoad.isEmpty {
            let ad = adsToLoad.removeFirst()
            let adRequest = GADRequest()
            ad.load(adRequest)
        }
    }
    
    // MARK: - GADAdNativeLoaderDelegate
    func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADUnifiedNativeAd) {
        aDNativeManager.nativeAds.append(nativeAd)
    }
    
    func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: GADRequestError) {
        print("\(adLoader) failed with error: \(error.localizedDescription)")
    }
    
    // In AppDelegate using Background refresh
    func adLoaderDidFinishLoading(_ adLoader: GADAdLoader) {
        indexNativeAdOutsideScreen = collectionView.indexCellOutsideTheScreen()?.row ?? 0
        updateTempNativeAds()
        addNativeAds()
        reloadCollection()
    }
    
    // MARK: - UICollectionView NativeAd data generation
    fileprivate func updateTempNativeAdsAfterTime() {
        let tempNACount = tepmtNativeAds.count
        tepmtNativeAds.removeAll()
        let lastItemsNativeAdsArray = aDNativeManager.nativeAds.suffix(aDNativeManager.numAdsToLoad)
        while tepmtNativeAds.count < tempNACount {
            for nAd in lastItemsNativeAdsArray {
                tepmtNativeAds.append(nAd)
            }
        }
    }
    
    fileprivate func updateTempNativeAds() {
        if !tepmtNativeAds.isEmpty {
            updateTempNativeAdsAfterTime()
        } else {
            tepmtNativeAds = aDNativeManager.nativeAds
        }
    }
    
    private func addNativeAds() {
        var index = indexNativeAdOutsideScreen
        if aDNativeManager.nativeAds.count <= 0 {
            return
        }
        
        for nativeAd in tepmtNativeAds {
            if index < collectionViewItems.count {
                collectionViewItems.insert(nativeAd as AnyObject, at: index)
                index += adIntervalNative
            } else {
                break
            }
        }
    }
}

// MARK: - UICollectionViewDataSource, UICollectionViewDelegate
extension BaseWallFeedViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateViewPostTimerWithDelay()
        showNavBar(scrollView)
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        hideNavBar(velocity)
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return collectionViewItems.isEmpty ? model.postList.count : collectionViewItems.count
    }
    
    fileprivate func showSizeFromCacheOrNot(_ postID: String, _ post: GetPostResponse?) -> CGSize {
        if let info = dataSourceUpdater.sizeCache[postID] {
            return info.sizeCell
        } else {
            let sizeInfo = SizeClass(post: post!)
            sizeInfo.maxContentLeaght = configurator.defaultPostTextLeaght
            dataSourceUpdater.sizeCache[postID] = sizeInfo
            sizeInfo.sizeCell = size(post: post!)
            return sizeInfo.sizeCell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        // Use fake cell to calculate height
        let post = collectionViewItems.isEmpty ? model.postList[indexPath.row] : collectionViewItems[indexPath.row] as? GetPostResponse
        if let postID = post?.post_id {
            return showSizeFromCacheOrNot(postID, post)
        } else if let _ = collectionViewItems[indexPath.row] as? GADBannerView {
            return CGSize(width: UIScreen.main.bounds.width, height: 100)
        } else if let _ = collectionViewItems[indexPath.row] as? GADUnifiedNativeAd {
            return CGSize(width: UIScreen.main.bounds.width, height: 300)
        } else {
            guard let _post = post else { return .zero}
            return size(post: _post) // ??
        }
    }
    
    func size(post: GetPostResponse, cell: BaseFeedCell? = nil) -> CGSize {
        let calculateCell = cell ?? tempCell
        calculateCell.clear()
        if let postID = post.post_id,
            let info = dataSourceUpdater.sizeCache[postID] {
            calculateCell.feedContentView.textLabel.maxLeaghtText = info.maxContentLeaght
        }
        calculateCell.layoutIfNeeded()
        calculateCell.loadPost(post: post, isShowFotter: showAdditionalFooter)
        let size = calculateCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return size
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.row < collectionViewItems.count {
            if let BannerView = collectionViewItems[indexPath.row] as? GADBannerView { // Banner Ad
                let reusableAdCell = collectionView.dequeueReusableCell(withReuseIdentifier: "BannerViewCell",
                                                                        for: indexPath)
                
                // Remove previous GADBannerView from the content view before adding a new one.
                for subview in reusableAdCell.contentView.subviews {
                    subview.removeFromSuperview()
                }
                
                reusableAdCell.contentView.addSubview(BannerView)
                // Center GADBannerView in the table cell's content view.
                DispatchQueue.main.async {
                    BannerView.center = reusableAdCell.contentView.center
                }
                return reusableAdCell
            } else if let nativeAd = collectionViewItems[indexPath.row] as? GADUnifiedNativeAd { // Native Ad
                /// Set the native ad's rootViewController to the current view controller.
                nativeAd.rootViewController = self
                
                let nativeAdCell = collectionView.dequeueReusableCell(withReuseIdentifier: "UnifiedNativeAdCell", for: indexPath)
                
                // Get the ad view from the Cell. The view hierarchy for this cell is defined in
                // UnifiedNativeAdCell.xib.
                let adView: GADUnifiedNativeAdView = nativeAdCell.contentView.subviews.first as! GADUnifiedNativeAdView
                
                // Associate the ad view with the ad object.
                // This is required to make the ad clickable.
                adView.nativeAd = nativeAd
                
                // Populate the ad view with the ad assets.
                (adView.headlineView as! UILabel).text = nativeAd.headline
                (adView.priceView as! UILabel).text = nativeAd.price
                if let starRating = nativeAd.starRating {
                    (adView.starRatingView as! UILabel).text = starRating.description + "\u{2605}"
                } else {
                    (adView.starRatingView as! UILabel).text = nil
                }
                (adView.bodyView as! UILabel).text = nativeAd.body
                (adView.advertiserView as! UILabel).text = nativeAd.advertiser
                // The SDK automatically turns off user interaction for assets that are part of the ad, but
                // it is still good to be explicit.
                (adView.callToActionView as! UIButton).isUserInteractionEnabled = false
                (adView.callToActionView as! UIButton).setTitle(
                    nativeAd.callToAction, for: UIControl.State.normal)
                
                return nativeAdCell
            }
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: self.cellIdentifier, for: indexPath)
        guard let feedCell = cell as? BaseFeedCell else {
            fatalError("Failed cell in BaseWallFeedVC")
        }
        cell.backgroundColor = ColorCompatibility.systemBackground
        self.updatePost(deque: true, cell: feedCell, at: indexPath)
        return cell
    }
    
    func showMoreActionAlertController(_ sender: UICollectionViewCell, ownerPostID: Int) -> UIAlertController? {
        guard let indexPath = collectionView.indexPath(for: sender) else { return nil }
        return showMoreActionAlertController(at: indexPath, ownerPostID: ownerPostID)
    }
    
    func showMoreActionAlertController(at indexPath: IndexPath, ownerPostID: Int) -> UIAlertController? {
        let post = collectionViewItems.isEmpty ? model.postList[indexPath.row] : collectionViewItems[indexPath.row] as! GetPostResponse
        guard let ownerID = post.user_id, let curentUserID = CurrentUser.sharedInstance.user_id else { return nil }
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if model is ProfileModel {
            let profileRemoveText = localized("dialog_delete", defaultString: "Удалить")
            if ownerPostID != curentUserID && ownerID != curentUserID {
                addAction(reportAction(post: post), to: alert)
            } else {
                addAction(removeAction(text: profileRemoveText, post: post, index: indexPath.row), to: alert)
            }
        }
        
        if model is FeedModel {
            let feedRemoveText = localized("feed_hide", defaultString: "Скрыть")
            addAction(removeAction(text: feedRemoveText, post: post, index: indexPath.row), to: alert)
            if ownerID != curentUserID {
                addAction(reportAction(post: post), to: alert)
            }
        }
        
        if model is GroupProfileModel {
            if let groupModel = model as? GroupProfileModel,
                let admins = groupModel.groupResponse?.admins {
                let filteredAdmin = admins.filter { $0.user_id == curentUserID }
                if filteredAdmin.count > 0 {
                    let groupRemoveText = localized("dialog_delete", defaultString: "Удалить")
                    addAction(removeAction(text: groupRemoveText, post: post, index: indexPath.row), to: alert)
                } else {
                    addAction(reportAction(post: post), to: alert)
                }
            }
        }
        
        if model is CommentsModel {
            addAction(reportAction(post: post), to: alert)
        }
        let cancel = UIAlertAction(title: localized("action_cancel", defaultString: "Отменить"), style: .cancel, handler: nil)
        alert.addAction(cancel)
        return alert
    }
    
    @objc func removePost(id: String, ownerID: Int) {
        
    }
    
    fileprivate func addAction(_ action: UIAlertAction?, to alertController: UIAlertController) {
        if let action = action {
            alertController.addAction(action)
        }
    }
    
    func removeAction(text: String, post: GetPostResponse, index: Int) -> UIAlertAction? {
        guard let postID = post.post_id, let ownerID = post.user_id else { return nil }
        let delete = UIAlertAction(title: text, style: .default)
        {  [weak self] (action) in
            self?.removePost(id: postID, ownerID: ownerID)
            //self?.removeCell(index: index)
        }
        return delete
    }
    
    func reportAction(post: GetPostResponse) -> UIAlertAction? {
        guard let postID = post.post_id, let ownerID = post.user_id else { return nil }
        let report = UIAlertAction(title: localized("action_report", defaultString: "Пожаловаться"), style: .default) { [weak self] (action) in
            guard let stongSelf = self,
                let contoller = RepotViewController.createReportVC(itemID: postID, authorID: ownerID, type: .post) else { return }
            stongSelf.present(contoller, animated: true, completion: nil)
        }
        return report
    }
    
    func createTempCell() -> BaseFeedCell {
        let cell = Bundle.main.loadNibNamed(self.cellIdentifier, owner: self, options: nil)?.first as! BaseFeedCell
        cell.delegate = self
        let width = UIScreen.main.bounds.width
        cell.updateConstranint(view: cell, to: width)
        cell.updateConstranint(view: cell.contentView, to: width)
        cell.feedContentView.heightImageContainer.isActive = true
        cell.feedContentView.isSizeCell = true
        return cell
    }
    
}

extension BaseWallFeedViewController: ImageDownloadDelegate {
    
    func cellDownloadImage(_ objectID: String, delta: CGFloat) {
        if let info = dataSourceUpdater.sizeCache[objectID],
            !info.isImageDownload {
            info.isImageDownload = true
            info.sizeCell.height += delta
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }
}

extension BaseWallFeedViewController: FeedActivityDelegate {
    
    
    @objc func singleLikePressed(value: Int, sender: UICollectionViewCell)
    {
        guard let indexPath = collectionView.indexPath(for: sender) else { return }
        let post = collectionViewItems[indexPath.row] as! GetPostResponse
        updateLike(with: post, sender: sender as? UpdateFooterDelegate)
    }
    
    func updateLike(with post: GetPostResponse, sender: UpdateFooterDelegate?) {
        dataSourceUpdater.sizeCache[post.post_id ?? ""] = nil
        _ = self.model.addCointsToPost(type: .post, author_id: post.user_id ?? 0, item_id: post.post_id ?? "", isLike: true, cost: 1)
        var items = createFotterItems(for: post)
        if let cell = sender {
            for (index, itemValue) in items.enumerated() {
                switch itemValue {
                case .likes(let isLike, let count):
                    let newCount = isLike ? -1 : 1
                    let coint = FeedCellFooterItem.likes(!isLike, count + newCount)
                    items.remove(at: index)
                    items.insert(coint, at: index)
                default: break
                }
            }
            cell.footerView.configureFootter(items)
        }
    }
    
    @objc func singleLikePressed(value: Int) {
        let post = collectionViewItems[0] as! GetPostResponse
        _ = self.model.addCointsToPost(type: .post, author_id: post.user_id ?? 0, item_id: post.post_id ?? "", isLike: true, cost: 1)
    }
    
    @objc func addoCointsPressed(value: Int, sender: UICollectionViewCell) {
        guard let indexPath = collectionView.indexPath(for: sender) else { return }
        let post = collectionViewItems[indexPath.row] as! GetPostResponse
        updateCoints(value, with: post, sender: sender as? UpdateFooterDelegate)
    }
    
    func updateCoints(_ value: Int, with post: GetPostResponse, sender: UpdateFooterDelegate?) {
        if value == 0
        {
            let alert = FCAlertView()
            //alert.colorScheme = UIColor.zontoBlue
            alert.firstButtonBackgroundColor = .white
            alert.secondButtonBackgroundColor = .white
            alert.hideSeparatorLineView = true
            alert.firstButtonTitleColor = .zontoBlue
            alert.doneButtonTitleColor = .zontoBlue
            alert.subTitleColor = UIColor(white: CGFloat(110) / 255, alpha: 1)
            alert.circleBackgroundColor = #colorLiteral(red: 1, green: 0.7333333333, blue: 0.01960784314, alpha: 1)// .red
            alert.fullCircleCustomImage = true
            alert.avoidCustomImageTint = true
            let image =  #imageLiteral(resourceName: "global_iconCoint")
            alert.showAlert(inView: self,
                            withTitle: nil,
                            withSubtitle: localized("alert_pay_custom_coins_title", defaultString: "Оцените этот пост"),
                            withCustomImage: image,
                            withDoneButtonTitle: "OK",
                            andButtons: nil)
            alert.addButton(localized("action_cancel", defaultString: "Отмена"), withActionBlock: {
                
            })
            alert.doneActionBlock({ [weak self] in
                if let string = alert.textField.text,
                    let cost = Int(string) {
                    _ = self?.model.addCointsToPost(type: .post, author_id: post.user_id ?? 0, item_id: post.post_id ?? "", isLike: false, cost: cost)
                }
            })
            alert.addTextField(withPlaceholder: localized("enter_count_coins", defaultString: "Введите количество ZONTO монет"), andTextReturn: { text in
                
            })
            
        }
        else
        {
            _ = self.model.addCointsToPost(type: .post, author_id: post.user_id ?? 0, item_id: post.post_id ?? "", isLike: false, cost: value)
        }
        if let cell = sender {
            update(footer: cell, with: post, value: value)
        }
    }
    
    private func update(footer: UpdateFooterDelegate, with post: GetPostResponse, value: Int) {
        var items = createFotterItems(for: post)
        
        for (index, itemValue) in items.enumerated() {
            switch itemValue {
            case .coints(let postCoint):
                let coint = FeedCellFooterItem.coints(postCoint + value)
                items.remove(at: index)
                items.insert(coint, at: index)
            default: break
            }
        }
        footer.footerView.configureFootter(items)
    }
    
    @objc func photoPressed(sender: UICollectionViewCell, selectedIndex: Int)
    {
        guard let index = collectionView.indexPath(for: sender) else { return }
        let urls = (collectionViewItems[index.row] as? GetPostResponse)?.media
        guard let _urls = urls else {
            fatalError("Failed to get urls for PhotosSubResponse")
        }
        let items = ZontoGalleryDatasource(photos: _urls)
        items.showWithIndex = selectedIndex
        self.presentImageGallery(items.controller)
    }
    
    func commentPressed(postID: String, ownerID: Int)
    {
        showPostDetail(postID)
    }
    
    @objc func sharePressed(postID: String, ownerID: Int, sender: UICollectionViewCell)
    {
        guard let index = collectionView.indexPath(for: sender) else { return }
        share(post: collectionViewItems[index.row] as! GetPostResponse)
    }
    
    func youtubePress(_ sender: UICollectionViewCell) {
        guard let index = collectionView.indexPath(for: sender) else { return }
        let info = collectionViewItems[index.row] as! GetPostResponse
        if let id = info.youtube?.first?.videoID,
            let url = URL(string: "http://www.youtube.com/watch?v=\(id)") {
            openUrl(url)
        }
    }
    
    func share(post: GetPostResponse) {
        guard let domain = shareDomaine(post: post) else { return }
        let ownerID: Int = abs(post.owner_id ?? 0)
        var textForShare = ZontoConstants.serverAddress + "/"
        textForShare += "\(domain)\(ownerID)#\(ZontoConstants.postAddress)\(post.post_id ?? "")"
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: localized("action_share", defaultString: "Share"), style: .default, handler: { [weak self] _ in
            textForShare.append("\n " + localized("feed_send_via_activity", defaultString: "Отправлено через iOS приложение Zonto.World"))
            let activity = UIActivityViewController(activityItems: [textForShare], applicationActivities: [])
            self?.present(activity, animated: true)
        }))
        
        alert.addAction(UIAlertAction(title: localized("share_in_zonto", defaultString: "Share in zonto"), style: .default, handler: { [weak self](_) in
            self?.showShareController(ShareObject(type: .object, value: textForShare))
        }))
        alert.addAction(UIAlertAction(title: localized("action_cancel", defaultString: "Cancel"), style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func showShareController(_ object: ShareObject<Any>?) {
        if let shareNvController = ShareConversationsController.createShareNavigationController(object) {
            self.present(shareNvController, animated: true, completion: nil)
        }
    }
    
    @objc func postPressed(postID: String, ownerID: Int, sender: UICollectionViewCell)
    {
        showPostDetail(postID)
    }
    
    func avatarPressedPressed(postID: String, ownerID: Int)
    {
        if ownerID > 0 {
            showWall(withUserID: ownerID)
        }
        else {
            showGroup(withID: ownerID)
        }
    }
    
    @objc func morePressed(_ sender: UICollectionViewCell) {
    }
    
    func showPostDetail(_ postID: String, scroll: Bool = false) {
        guard let post = collectionViewItems.first(where: { return ($0 as? GetPostResponse)?.post_id == postID }),
            let ownerID = (post as! GetPostResponse).owner_id else { return }
        let postDetail = PostDetailData(postID: postID, ownerID: ownerID)
        if let controller = DetailPostViewController.createDetailPostScreen(postDetail) {
            self.navigationController?.pushViewController(controller, animated: true)
        }
    }
    
    func showGroup(withID: Int) {
        if let groupController = self as? GroupWallViewController,
            groupController.groupID == abs(withID) {
            return
        }
        let storyboard = UIStoryboard(name: "GroupUI", bundle: nil)
        let controller = storyboard.instantiateViewController(withIdentifier: "GroupProfileVC")
        let groupController = controller as! GroupWallViewController
        groupController.groupID = abs(withID)
        self.navigationController?.pushViewController(controller, animated: true)
    }
    
    func showWall(withUserID: Int) {
        if let wallModel = self.model as? ProfileModel,
            wallModel.userID == withUserID {
            return
        }
        let controller = UserWallViewController.createUserProfileContoller(with: withUserID)
        self.navigationController?.pushViewController(controller, animated: true)
    }
    
    func showLikes(_ sender: UICollectionViewCell) {
        guard let indexPath = collectionView.indexPath(for: sender) else { return }
        let likeModel = LikesPeopleModel()
        if let controller = self.createController(with: likeModel) {
            likeModel.postInfo = collectionViewItems[indexPath.row] as? GetPostResponse
            navigationController?.pushViewController(controller, animated: true)
        }
    }
    
    func createController(with model: BaseListModel) -> TableList? {
        if let controller = UIStoryboard(name: "Table", bundle: nil).instantiateViewController(withIdentifier: "TableList") as? TableList {
            model.modelDelegate = controller
            controller.model = model
            model.controler = controller
            return controller
        }
        return nil
    }
}

extension BaseWallFeedViewController: BaseModelDelegate {
    
    
    @objc func loadMore(_ handler: (() -> Void)?)
    {
    }
    
    @objc func refresh()
    {
    }
    
    @objc func getData(hasNewContent: Bool)
    {
        collectionRefreshControl.endRefreshing()
        if hasNewContent {
            reloadCollection()
            let updatePost = dataSourceUpdater.sizeCache.filter({ $0.value.isNeedRefreshSize })
            updateSize(for: updatePost)
        }
    }
    
    func updateSize(for sizes: [String : SizeClass]) {
        var posts = sizes
        let updateValue = posts.prefix(5)
        updateValue.forEach({ (key, value) in
            if let post = self.collectionViewItems.first(where: { ($0 as? GetPostResponse)?.post_id == key })  {
                value.sizeCell = self.size(post: post as! GetPostResponse)
            }
            value.isNeedRefreshSize = false
            posts[key] = nil
        })
        reloadCollection()
        DispatchQueue.main.async { [weak self] in
            if posts.count > 0 {
                self?.updateSize(for: posts)
            }
        }
    }
    
    
    @objc func get(error: Error)
    {
        collectionRefreshControl.endRefreshing()
    }
}

extension BaseWallFeedViewController: ZontoActivityViewDelegate
{
    func openUrl(_ url: URL) {
        self.present(Browser(url: url), animated: true, completion: nil)
    }
    
    func openInnerLink(_ view: UIViewController) {
        self.navigationController?.pushViewController(view, animated: true)
    }
    
    @objc func openHastagWall(_ hashtag: String) {
        let storyboard = UIStoryboard(name: "MainUI", bundle: nil)
        if let mediaController = storyboard.instantiateViewController(withIdentifier: "HashTagFeedViewController") as? HashTagFeedViewController {
            mediaController.tagString = hashtag
            navigationController?.pushViewController(mediaController, animated: true)
        }
    }
}

extension BaseWallFeedViewController: BaseFeedDelegate
{
    func showCommentsOf(postID: String) {
        showPostDetail(postID, scroll: true)
    }
    
    func expandTextContent(_ sender: UICollectionViewCell) {
        guard let indexPath = collectionView.indexPath(for: sender),
            let postID = (collectionViewItems[indexPath.row] as! GetPostResponse).post_id else { return }
        if let info = dataSourceUpdater.sizeCache[postID] {
            info.maxContentLeaght = Int.max
            info.sizeCell = size(post: collectionViewItems[indexPath.row] as! GetPostResponse)
            collectionView.performBatchUpdates({
                self.collectionView.reloadItems(at: [indexPath])
            }, completion: nil)
            updateViewPostTimerWithDelay()
        }
    }
}

// MARK: - Hide and show navigation bar
extension BaseWallFeedViewController {
    fileprivate func getVC(completion: (NewsFeedViewController) -> Void) {
        if let feedController = navigationController?.visibleViewController as? FeedTabViewController, let newsFeedController = feedController.children.first as? NewsFeedViewController {
            completion(newsFeedController)
        }
    }
    
    fileprivate func showNavBar(_ scrollView: UIScrollView) {
        if (scrollView.panGestureRecognizer.translation(in: scrollView.superview).y > 200) {
            getVC { (newsFeedController) in
                newsFeedController.sectionHeaderView.isHidden = false
            }
            
            guard !(view.findViewController() is UserWallViewController), !(view.findViewController() is DetailPostViewController), !(view.findViewController() is GroupWallViewController), !(view.findViewController() is HashTagFeedViewController)  else { return }
            self.navigationController?.setNavigationBarHidden(false, animated: true)
        }
    }
    
    fileprivate func hideNavBar(_ velocity: CGPoint) {
        if (velocity.y > 0) {
            getVC { (newsFeedController) in
                newsFeedController.sectionHeaderView.isHidden = true
            }
            
            guard !(view.findViewController() is UserWallViewController), !(view.findViewController() is DetailPostViewController), !(view.findViewController() is GroupWallViewController), !(view.findViewController() is HashTagFeedViewController) else { return }
            UIView.animate(withDuration: 0.1, animations: {
                self.navigationController?.setNavigationBarHidden(true, animated: true)
            }, completion: nil)
        }
    }
}
