import 'package:cake_wallet/core/auth_service.dart';
import 'package:cake_wallet/core/wallet_loading_service.dart';
import 'package:cake_wallet/src/screens/auth/auth_page.dart';
import 'package:cake_wallet/src/screens/wallet_unlock/wallet_unlock_arguments.dart';
import 'package:cake_wallet/store/settings_store.dart';
import 'package:hive/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:cake_wallet/di.dart';
import 'package:cake_wallet/store/app_store.dart';
import 'package:cw_core/wallet_service.dart';
import 'package:cake_wallet/view_model/wallet_list/wallet_list_item.dart';
import 'package:cw_core/wallet_info.dart';
import 'package:cw_core/wallet_type.dart';
import 'package:cake_wallet/wallet_types.g.dart';
import 'package:cake_wallet/routes.dart';
import 'package:cake_wallet/generated/i18n.dart';
import 'package:flutter/material.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:cake_wallet/utils/show_bar.dart';

part 'wallet_list_view_model.g.dart';

class WalletListViewModel = WalletListViewModelBase with _$WalletListViewModel;

abstract class WalletListViewModelBase with Store {
  WalletListViewModelBase(
    this._walletInfoSource,
    this._appStore,
    this._walletLoadingService,
    this._authService,
  ) : wallets = ObservableList<WalletListItem>() {
    _updateList();
    reaction((_) => _appStore.wallet, (_) => _updateList());
  }

  @observable
  ObservableList<WalletListItem> wallets;

  final AppStore _appStore;
  final Box<WalletInfo> _walletInfoSource;
  final WalletLoadingService _walletLoadingService;
  final AuthService _authService;

  WalletType get currentWalletType => _appStore.wallet!.type;

  @action
  Future<void> loadWallet(WalletListItem walletItem) async {
    final wallet =
        await _walletLoadingService.load(walletItem.type, walletItem.name);
    _appStore.changeCurrentWallet(wallet);
    _updateList();
  }

  @action
  Future<void> remove(WalletListItem wallet) async {
    final walletService = getIt.get<WalletService>(param1: wallet.type);
    await walletService.remove(wallet.name);
    await _walletInfoSource.delete(wallet.key);
    _updateList();
  }

  void _updateList() {
    wallets.clear();
    wallets.addAll(
      _walletInfoSource.values.map(
        (info) => WalletListItem(
          name: info.name,
          type: info.type,
          key: info.key,
          isCurrent: info.name == _appStore.wallet!.name &&
              info.type == _appStore.wallet!.type,
          isEnabled: availableWalletTypes.contains(info.type),
        ),
      ),
    );
  }

  bool checkIfAuthRequired() {
    return _authService.requireAuth();
  }

  Flushbar<void>? _progressBar;

  void changeProcessText(String text, BuildContext context) {
    _progressBar = createBar<void>(text, duration: null)..show(context);
  }

  void hideProgressText() {
    _progressBar?.dismiss();
    _progressBar = null;
  }

  @action
  Future<void> authWallet(WalletListItem wallet, BuildContext context) async {
    if (await checkIfAuthRequired()) {
      if (SettingsStoreBase.walletPasswordDirectInput) {
        Navigator.of(context).pushNamed(Routes.walletUnlockLoadable,
            arguments: WalletUnlockArguments(
                callback: (bool isAuthenticatedSuccessfully,
                    AuthPageState auth) async {
                  if (isAuthenticatedSuccessfully) {
                    auth.close();
                  }
                },
                walletName: wallet.name,
                walletType: wallet.type));
        return;
      }

      await Navigator.of(context).pushNamed(Routes.auth, arguments:
          (bool isAuthenticatedSuccessfully, AuthPageState auth) async {
        if (!isAuthenticatedSuccessfully) {
          return;
        }

        try {
          auth.changeProcessText(
              S.of(context).wallet_list_loading_wallet(wallet.name));
          await loadWallet(wallet);
          auth.hideProgressText();
          auth.close();
        } catch (e) {
          auth.changeProcessText(S
              .of(context)
              .wallet_list_failed_to_load(wallet.name, e.toString()));
        }
      });
    } else {
      try {
        changeProcessText(
            S.of(context).wallet_list_loading_wallet(wallet.name), context);
        await loadWallet(wallet);
        hideProgressText();
      } catch (e) {
        changeProcessText(
            S.of(context).wallet_list_failed_to_load(wallet.name, e.toString()),
            context);
      }
    }
  }
}
