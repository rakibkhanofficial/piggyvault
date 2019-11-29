import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:piggy_flutter/models/api_response.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:piggy_flutter/models/models.dart';
import 'package:piggy_flutter/utils/uidata.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PiggyApiClient {
  static const baseUrl = 'https://piggyvault.in';
  // static const baseUrl = 'http://10.0.2.2:21021';
  // static const baseUrl = 'http://localhost:21021';
  final http.Client httpClient;

  PiggyApiClient({@required this.httpClient}) : assert(httpClient != null);

  Future<IsTenantAvailableResult> isTenantAvailable(String tenancyName) async {
    final tenantUrl = '$baseUrl/api/services/app/Account/IsTenantAvailable';
    final response =
        await this.postAsync(tenantUrl, {"tenancyName": tenancyName});

    if (!response.success) {
      throw Exception('invalid credentials');
    }

    return IsTenantAvailableResult.fromJson(response.result);
  }

  Future<AuthenticateResult> authenticate(
      {@required String usernameOrEmailAddress,
      @required String password}) async {
    final loginUrl = '$baseUrl/api/TokenAuth/Authenticate';
    final loginResult = await this.postAsync(loginUrl, {
      "usernameOrEmailAddress": usernameOrEmailAddress,
      "password": password,
      "rememberClient": true
    });

    if (!loginResult.success) {
      throw Exception(loginResult.error);
    }
    return AuthenticateResult.fromJson(loginResult.result);
  }

  Future<User> getCurrentLoginInformations() async {
    final userUrl =
        '$baseUrl/api/services/app/session/GetCurrentLoginInformations';
    final response = await this.getAsync(userUrl);

    if (response.success && response.result['user'] != null) {
      return User.fromJson(response.result['user']);
    }

    return null;
  }

  Future<TransactionSummary> getTransactionSummary(String duration) async {
    var result = await getAsync<dynamic>(
        '$baseUrl/api/services/app/Transaction/GetSummary?duration=$duration');

    if (result.success) {
      return TransactionSummary.fromJson(result.result);
    }

    return null;
  }

  Future<TenantAccountsResult> getTenantAccounts() async {
    List<Account> userAccountItems = [];
    List<Account> familyAccountItems = [];
    var result = await getAsync<dynamic>(
        '$baseUrl/api/services/app/account/GetTenantAccounts');

    if (result.success) {
      result.result['userAccounts']['items'].forEach((account) {
        userAccountItems.add(Account.fromJson(account));
      });
      result.result['otherMembersAccounts']['items'].forEach((account) {
        familyAccountItems.add(Account.fromJson(account));
      });
    }

    return TenantAccountsResult(
        familyAccounts: familyAccountItems, userAccounts: userAccountItems);
  }

  Future<List<Category>> getTenantCategories() async {
    List<Category> tenantCategories = [];

    var result = await getAsync(
        '$baseUrl/api/services/app/Category/GetTenantCategories');

    if (result.success) {
      result.result['items'].forEach(
          (category) => tenantCategories.add(Category.fromJson(category)));
    }
    return tenantCategories;
  }

  Future<ApiResponse<dynamic>> createOrUpdateTransaction(
      TransactionEditDto input) async {
    final result = await postAsync(
        '$baseUrl/api/services/app/transaction/CreateOrUpdateTransaction', {
      "id": input.id,
      "description": input.description,
      "amount": input.amount,
      "categoryId": input.categoryId,
      "accountId": input.accountId,
      "transactionTime": input.transactionTime
    });

    return result;
  }

  Future<ApiResponse<dynamic>> transfer(TransferInput input) async {
    final result =
        await postAsync('$baseUrl/api/services/app/transaction/transfer', {
      "id": input.id,
      "description": input.description,
      "amount": input.amount,
      "toAmount": input.toAmount,
      "categoryId": input.categoryId,
      "accountId": input.accountId,
      "toAccountId": input.toAccountId,
      "transactionTime": input.transactionTime
    });

    return result;
  }

  Future<List<Transaction>> getTransactions(GetTransactionsInput input) async {
    List<Transaction> transactions = [];

    var params = '';

    if (input.type != null) params += 'type=${input.type}';

    if (input.accountId != null) params += '&accountId=${input.accountId}';

    if (input.startDate != null && input.startDate.toString() != '')
      params += '&startDate=${input.startDate}';

    if (input.endDate != null && input.endDate.toString() != '')
      params += '&endDate=${input.endDate}';

    var result = await getAsync<dynamic>(
        '$baseUrl/api/services/app/transaction/GetTransactions?$params');

    if (result.success) {
      result.result['items'].forEach((transaction) {
        transactions.add(Transaction.fromJson(transaction));
      });
    }
    return transactions;
  }

  Future<Account> getAccountDetails(String accountId) async {
    var result = await getAsync<dynamic>(
        '$baseUrl/api/services/app/account/GetAccountDetails?id=$accountId');

    if (result.success) {
      return Account.fromJson(result.result);
    }

    return null;
  }

// utils

  Future<ApiResponse<T>> getAsync<T>(String resourcePath) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString(UIData.authToken);
    var tenantId = prefs.getInt(UIData.tenantId);
    var response = await this.httpClient.get(resourcePath, headers: {
      'Content-type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Piggy-TenantId': tenantId.toString()
    });
    return processResponse<T>(response);
  }

  Future<ApiResponse<T>> postAsync<T>(String resourcePath, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString(UIData.authToken);
    var tenantId = prefs.getInt(UIData.tenantId);

    var content = json.encoder.convert(data);
    Map<String, String> headers;

    if (token == null) {
      headers = {
        'Content-type': 'application/json',
        'Accept': 'application/json',
        'Piggy-TenantId': tenantId.toString()
      };
    } else {
      headers = {
        'Content-type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Piggy-TenantId': tenantId.toString()
      };
    }

    // print(content);
    var response =
        await http.post(resourcePath, body: content, headers: headers);
    return processResponse<T>(response);
  }

  ApiResponse<T> processResponse<T>(http.Response response) {
    try {
      // if (!((response.statusCode < 200) ||
      //     (response.statusCode >= 300) ||
      //     (response.body == null))) {
      var jsonResult = response.body;
      dynamic parsedJson = jsonDecode(jsonResult);

      // print(jsonResult);

      var output = ApiResponse<T>(
        result: parsedJson["result"],
        success: parsedJson["success"],
        unAuthorizedRequest: parsedJson['unAuthorizedRequest'],
      );

      if (!output.success) {
        output.error = parsedJson["error"]["message"];
      }
      return output;
    } catch (e) {
      return ApiResponse<T>(
          result: null,
          success: false,
          unAuthorizedRequest: false,
          error: 'Something went wrong. Please try again');
    }
  }
}