import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const String kGoMenProMonthlyProductId = 'gomen.pro.monthly';

class GoMenBillingService extends ChangeNotifier {
  GoMenBillingService({
    required Future<void> Function(bool isPro) onEntitlementChanged,
  }) : _onEntitlementChanged = onEntitlementChanged;

  final Future<void> Function(bool isPro) _onEntitlementChanged;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool isStoreAvailable = false;
  bool isLoading = true;
  bool isPurchasePending = false;
  String? errorText;
  ProductDetails? product;

  Future<void> init() async {
    if (_purchaseSub != null) return;

    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () {
        _purchaseSub?.cancel();
      },
      onError: (Object error) {
        errorText = 'purchaseStream error: $error';
        isPurchasePending = false;
        notifyListeners();
      },
    );

    await reload();
  }

  Future<void> reload() async {
    isLoading = true;
    errorText = null;
    notifyListeners();

    final available = await _iap.isAvailable();
    isStoreAvailable = available;

    if (!available) {
      isLoading = false;
      errorText = 'App Store に接続できません。';
      notifyListeners();
      return;
    }

    final response = await _iap.queryProductDetails({
      kGoMenProMonthlyProductId,
    });

    if (response.error != null) {
      isLoading = false;
      errorText = response.error!.message;
      notifyListeners();
      return;
    }

    if (response.notFoundIDs.isNotEmpty) {
      isLoading = false;
      errorText = '商品IDが見つかりません: ${response.notFoundIDs.join(", ")}';
      notifyListeners();
      return;
    }

    if (response.productDetails.isEmpty) {
      isLoading = false;
      errorText = '商品情報が取得できません。App Store Connect 側を確認してください。';
      notifyListeners();
      return;
    }

    product = response.productDetails.first;
    isLoading = false;
    notifyListeners();
  }

  Future<void> buyPro() async {
    final target = product;
    if (target == null) return;

    errorText = null;
    isPurchasePending = true;
    notifyListeners();

    final purchaseParam = PurchaseParam(productDetails: target);
    final launched = await _iap.buyNonConsumable(purchaseParam: purchaseParam);

    if (!launched) {
      isPurchasePending = false;
      errorText = '購入画面を開けませんでした。';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    errorText = null;
    isPurchasePending = true;
    notifyListeners();
    await _iap.restorePurchases();
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      if (purchase.productID != kGoMenProMonthlyProductId) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.pending) {
        isPurchasePending = true;
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        isPurchasePending = false;
        errorText = purchase.error?.message ?? '購入エラーが発生しました。';
        notifyListeners();
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        // 次段階で backend 側の検証成功後に true にする。
        await _onEntitlementChanged(true);
        isPurchasePending = false;
        errorText = null;
        notifyListeners();
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
