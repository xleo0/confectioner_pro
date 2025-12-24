// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_key_in_widget_constructors, library_private_types_in_public_api, unnecessary_string_interpolations, unreachable_switch_default, deprecated_member_use, unnecessary_to_list_in_spreads, depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'dart:collection';
import 'dart:math';

// ===========================================================================
// 1. ТОЧКА ВХОДА (MAIN)
// ===========================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  runApp(
    ChangeNotifierProvider(
      create: (context) => PastryProvider(),
      child: PastryProApp(),
    ),
  );
}

// ===========================================================================
// 2. МОДЕЛИ ДАННЫХ
// ===========================================================================
enum OrderStatus { inProgress, ready, completed }
enum IngredientType { ingredient, decoration, packaging }

class Ingredient {
  String id;
  String name;
  double price;
  double packageSize;
  IngredientType type;

  Ingredient({
    required this.id,
    required this.name,
    required this.price,
    required this.packageSize,
    this.type = IngredientType.ingredient,
  });
  double get pricePerUnit => (packageSize > 0) ? price / packageSize : 0;
}

class RecipeComponent {
  String ingredientId;
  double quantity;

  RecipeComponent({required this.ingredientId, required this.quantity});
}

class InventoryItem {
  String id;
  String productId;
  String productName;
  int quantity;
  int availableQuantity;
  DateTime productionDate;
  double unitCostAtTimeOfProduction;

  InventoryItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.productionDate,
    required this.unitCostAtTimeOfProduction,
    int? availableQuantity,
  }) : availableQuantity = availableQuantity ?? quantity;
}

class Product {
  String id;
  String name;
  List<RecipeComponent> ingredients;
  int producedQuantity;

  Product({
    required this.id,
    required this.name,
    this.ingredients = const [],
    this.producedQuantity = 1,
  });

  double getCost(List<Ingredient> allIngredients) {
    double totalCost = 0.0;
    for (var component in ingredients) {
      try {
        final ingredient = allIngredients
            .firstWhere((ing) => ing.id == component.ingredientId);
        totalCost += ingredient.pricePerUnit * component.quantity;
      } catch (e) {
        // Ингредиент не найден
      }
    }
    return totalCost;
  }

  double getUnitCost(List<Ingredient> allIngredients) {
    if (producedQuantity <= 0) return 0.0;
    return getCost(allIngredients) / producedQuantity;
  }
}

class OrderDecorationPackagingItem {
  String id;
  String? itemId;
  double quantity;
  String itemName;
  double itemPriceAtTime;

  OrderDecorationPackagingItem({
    required this.id,
    this.itemId,
    this.quantity = 0,
    required this.itemName,
    required this.itemPriceAtTime,
  });
}

// === НОВАЯ МОДЕЛЬ: Изделие в заказе ===
class OrderItem {
  String id;
  String productId;
  String productName;
  String? inventoryItemId;
  double unitCostFromInventory;
  int quantity;
  double sellingPrice;
  List<OrderDecorationPackagingItem> decorations;
  List<OrderDecorationPackagingItem> packaging;

  OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.inventoryItemId,
    this.unitCostFromInventory = 0,
    this.quantity = 1,
    this.sellingPrice = 0,
    List<OrderDecorationPackagingItem>? decorations,
    List<OrderDecorationPackagingItem>? packaging,
  })  : decorations = decorations ?? [],
        packaging = packaging ?? [];

  double getTotalCost() {
    double total = unitCostFromInventory * quantity;
    for (var d in decorations) {
      total += d.itemPriceAtTime * d.quantity * quantity;
    }
    for (var p in packaging) {
      total += p.itemPriceAtTime * p.quantity * quantity;
    }
    return total;
  }

  double getTotalPrice() => sellingPrice * quantity;
  double getProfit() => getTotalPrice() - getTotalCost();

  double getDecorationCost() {
    double total = 0;
    for (var d in decorations) {
      total += d.itemPriceAtTime * d.quantity * quantity;
    }
    return total;
  }

  double getPackagingCost() {
    double total = 0;
    for (var p in packaging) {
      total += p.itemPriceAtTime * p.quantity * quantity;
    }
    return total;
  }

  String get tabName => productName.isNotEmpty ? productName : 'Новое изделие';
}

// === ОБНОВЛЕННАЯ МОДЕЛЬ ЗАКАЗА ===
class Order {
  String id;
  String customerName;
  String? customerPhone;
  DateTime orderDate;
  OrderStatus status;
  List<OrderItem> items;

  Order({
    required this.id,
    required this.customerName,
    this.customerPhone,
    required this.orderDate,
    this.status = OrderStatus.inProgress,
    List<OrderItem>? items,
  }) : items = items ?? [];

  double getTotalCost() {
    return items.fold(0.0, (sum, item) => sum + item.getTotalCost());
  }

  double getTotalPrice() {
    return items.fold(0.0, (sum, item) => sum + item.getTotalPrice());
  }

  double getProfit() => getTotalPrice() - getTotalCost();

  double getTotalDecorationCost() {
    return items.fold(0.0, (sum, item) => sum + item.getDecorationCost());
  }

  double getTotalPackagingCost() {
    return items.fold(0.0, (sum, item) => sum + item.getPackagingCost());
  }

  String get shortDescription {
    if (items.isEmpty) return 'Пустой заказ';
    if (items.length == 1) return items.first.productName;
    return '${items.first.productName} +${items.length - 1}';
  }

  String get itemsList {
    return items.map((i) => '${i.productName} x${i.quantity}').join(', ');
  }
}

// ===========================================================================
// 3. УПРАВЛЕНИЕ СОСТОЯНИЕМ (PROVIDER)
// ===========================================================================
class PastryProvider with ChangeNotifier {
  final List<Ingredient> _ingredients = [
    Ingredient(
        id: 'ing1',
        name: 'Мука пшеничная',
        price: 60,
        packageSize: 1000,
        type: IngredientType.ingredient),
    Ingredient(
        id: 'ing2',
        name: 'Сахар',
        price: 80,
        packageSize: 1000,
        type: IngredientType.ingredient),
    Ingredient(
        id: 'ing3',
        name: 'Сливочное масло',
        price: 150,
        packageSize: 180,
        type: IngredientType.ingredient),
    Ingredient(
        id: 'dec1',
        name: 'Свежие ягоды',
        price: 250,
        packageSize: 100,
        type: IngredientType.decoration),
    Ingredient(
        id: 'pack1',
        name: 'Коробка для торта',
        price: 100,
        packageSize: 1,
        type: IngredientType.packaging),
  ];
  final List<Product> _products = [
    Product(
        id: 'prod1',
        name: 'Торт "Медовик"',
        producedQuantity: 1,
        ingredients: [
          RecipeComponent(ingredientId: 'ing1', quantity: 300),
          RecipeComponent(ingredientId: 'ing2', quantity: 200),
          RecipeComponent(ingredientId: 'ing3', quantity: 180)
        ])
  ];
  final List<Order> _orders = [];
  final List<InventoryItem> _inventory = [];

  UnmodifiableListView<Ingredient> get ingredients =>
      UnmodifiableListView(_ingredients);
  UnmodifiableListView<Product> get products => UnmodifiableListView(_products);
  UnmodifiableListView<Order> get orders => UnmodifiableListView(_orders);
  UnmodifiableListView<InventoryItem> get inventory =>
      UnmodifiableListView(_inventory);

  List<Ingredient> getIngredientsByType(IngredientType type) =>
      _ingredients.where((ing) => ing.type == type).toList();

  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      Random().nextInt(999).toString();

  void addIngredient(Ingredient ingredient) {
    ingredient.id = _generateId();
    _ingredients.add(ingredient);
    notifyListeners();
  }

  void updateIngredient(Ingredient updatedIngredient) {
    final index = _ingredients.indexWhere((i) => i.id == updatedIngredient.id);
    if (index != -1) {
      _ingredients[index] = updatedIngredient;
      notifyListeners();
    }
  }

  void deleteIngredient(String id) {
    _ingredients.removeWhere((ingredient) => ingredient.id == id);
    notifyListeners();
  }

  void addProduct(Product product) {
    product.id = _generateId();
    _products.add(product);
    notifyListeners();
  }

  void updateProduct(Product updatedProduct) {
    final index = _products.indexWhere((p) => p.id == updatedProduct.id);
    if (index != -1) {
      _products[index] = updatedProduct;
      notifyListeners();
    }
  }

  void deleteProduct(String id) {
    _products.removeWhere((product) => product.id == id);
    notifyListeners();
  }

  void addInventoryItem(InventoryItem item) {
    item.id = _generateId();
    _inventory.add(item);
    notifyListeners();
  }

  void updateInventoryItem(InventoryItem updatedItem) {
    final index = _inventory.indexWhere((i) => i.id == updatedItem.id);
    if (index != -1) {
      _inventory[index] = updatedItem;
      notifyListeners();
    }
  }

  void deleteInventoryItem(String id) {
    _inventory.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void addProductToInventory(
      String productId, int quantity, DateTime productionDate) {
    final product = _products.firstWhere((p) => p.id == productId,
        orElse: () => throw Exception('Product not found'));
    final unitCost = product.getUnitCost(_ingredients);

    if (unitCost <= 0 || quantity <= 0) {
      throw Exception('Неверные данные изделия или количество');
    }

    final existingIndex = _inventory.indexWhere((item) =>
        item.productId == productId &&
        isSameDay(item.productionDate, productionDate));

    if (existingIndex != -1) {
      _inventory[existingIndex].quantity += quantity;
      _inventory[existingIndex].availableQuantity += quantity;
      notifyListeners();
    } else {
      final inventoryItem = InventoryItem(
        id: '',
        productId: product.id,
        productName: product.name,
        quantity: quantity,
        productionDate: productionDate,
        unitCostAtTimeOfProduction: unitCost,
        availableQuantity: quantity,
      );
      addInventoryItem(inventoryItem);
    }
  }

  List<InventoryItem> getAvailableInventoryForProduct(String productId) =>
      _inventory
          .where((item) =>
              item.productId == productId && item.availableQuantity > 0)
          .toList();

  // === ОБНОВЛЕННЫЕ МЕТОДЫ ДЛЯ ЗАКАЗОВ ===
  void addOrder(Order order) {
    order.id = _generateId();
    _orders.add(order);

    // Обновляем запасы для всех изделий в заказе
    for (var item in order.items) {
      if (item.inventoryItemId != null) {
        final inventoryIndex =
            _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
        if (inventoryIndex != -1) {
          _inventory[inventoryIndex].availableQuantity -= item.quantity;
        }
      }
    }
    notifyListeners();
  }

  void updateOrder(Order updatedOrder) {
    final index = _orders.indexWhere((o) => o.id == updatedOrder.id);
    if (index != -1) {
      final oldOrder = _orders[index];

      // Возвращаем старые изделия в запасы
      for (var item in oldOrder.items) {
        if (item.inventoryItemId != null) {
          final invIndex =
              _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
          if (invIndex != -1) {
            _inventory[invIndex].availableQuantity += item.quantity;
          }
        }
      }

      _orders[index] = updatedOrder;

      // Списываем новые изделия из запасов
      for (var item in updatedOrder.items) {
        if (item.inventoryItemId != null) {
          final invIndex =
              _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
          if (invIndex != -1) {
            _inventory[invIndex].availableQuantity -= item.quantity;
          }
        }
      }

      notifyListeners();
    }
  }

  void deleteOrder(String id) {
    final orderIndex = _orders.indexWhere((order) => order.id == id);
    if (orderIndex != -1) {
      final orderToDelete = _orders[orderIndex];

      // Возвращаем все изделия в запасы
      for (var item in orderToDelete.items) {
        if (item.inventoryItemId != null) {
          final invIndex =
              _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
          if (invIndex != -1) {
            _inventory[invIndex].availableQuantity += item.quantity;
          }
        }
      }

      _orders.removeAt(orderIndex);
      notifyListeners();
    }
  }

  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    final orderIndex = _orders.indexWhere((o) => o.id == orderId);
    if (orderIndex != -1) {
      _orders[orderIndex].status = newStatus;
      notifyListeners();
    }
  }

  Product getProductById(String id) => _products.firstWhere((p) => p.id == id,
      orElse: () =>
          Product(id: 'not_found', name: 'Изделие удалено', producedQuantity: 0));

  Ingredient getIngredientById(String id) => _ingredients.firstWhere(
      (i) => i.id == id,
      orElse: () => Ingredient(
          id: 'not_found',
          name: 'Ингредиент удален',
          price: 0,
          packageSize: 0,
          type: IngredientType.ingredient));

  Map<String, double> getStatistics() {
    final completedOrders =
        _orders.where((o) => o.status == OrderStatus.completed);
    double totalRevenue = 0, totalCost = 0;
    for (var order in completedOrders) {
      totalRevenue += order.getTotalPrice();
      totalCost += order.getTotalCost();
    }
    return {
      'revenue': totalRevenue,
      'cost': totalCost,
      'profit': totalRevenue - totalCost,
      'orderCount': completedOrders.length.toDouble()
    };
  }

  Map<String, double> getStatisticsForPeriod(
      DateTime startDate, DateTime endDate) {
    final completedOrders = _orders
        .where((o) => o.status == OrderStatus.completed)
        .where((o) =>
            (o.orderDate.isAfter(startDate) ||
                isSameDay(o.orderDate, startDate)) &&
            (o.orderDate.isBefore(endDate) || isSameDay(o.orderDate, endDate)))
        .toList();
    double totalRevenue = 0, totalCost = 0;
    Set<String> uniqueCustomers = {};
    for (var order in completedOrders) {
      totalRevenue += order.getTotalPrice();
      totalCost += order.getTotalCost();
      uniqueCustomers.add(order.customerName);
    }
    return {
      'revenue': totalRevenue,
      'cost': totalCost,
      'profit': totalRevenue - totalCost,
      'orderCount': completedOrders.length.toDouble(),
      'customerCount': uniqueCustomers.length.toDouble(),
    };
  }
}

// ===========================================================================
// 4. ГЛАВНОЕ ПРИЛОЖЕНИЕ И НАВИГАЦИЯ
// ===========================================================================
class PastryProApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Кондитер Про',
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ru', 'RU'),
      ],
      theme: ThemeData(
          primarySwatch: Colors.pink,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  DateTime _selectedDayForNewOrder = DateTime.now();
  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  void _updateSelectedDay(DateTime? day) {
    if (day != null) {
      setState(() => _selectedDayForNewOrder = day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      OrdersScreen(onDaySelected: _updateSelectedDay),
      ProductsScreen(),
      IngredientsMainScreen(),
      InventoryScreen(),
      StatisticsScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
          title: Text('Кондитер Про'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'Заказы'),
          BottomNavigationBarItem(icon: Icon(Icons.cake), label: 'Изделия'),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: 'Справочник'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Запасы'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Статистика'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex < 4
          ? FloatingActionButton(
              child: Icon(Icons.add),
              onPressed: () {
                if (_selectedIndex == 0) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => OrderEditScreen(
                              selectedDate: _selectedDayForNewOrder)));
                } else if (_selectedIndex == 1) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (context) => ProductEditScreen()));
                } else if (_selectedIndex == 2) {
                  _showIngredientTypeDialog(context);
                } else if (_selectedIndex == 3) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (context) => AddToInventoryScreen()));
                }
              },
            )
          : null,
    );
  }

  void _showIngredientTypeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Выберите тип'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Ингредиенты'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              IngredientEditScreen(type: IngredientType.ingredient)));
                },
              ),
              ListTile(
                title: Text('Украшения'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              IngredientEditScreen(type: IngredientType.decoration)));
                },
              ),
              ListTile(
                title: Text('Упаковка'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              IngredientEditScreen(type: IngredientType.packaging)));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- ЭКРАН ДОБАВЛЕНИЯ В ЗАПАСЫ ---
class AddToInventoryScreen extends StatefulWidget {
  @override
  _AddToInventoryScreenState createState() => _AddToInventoryScreenState();
}

class _AddToInventoryScreenState extends State<AddToInventoryScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedProductId;
  late TextEditingController _quantityController;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: Text('Добавить в запасы')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Выберите изделие:',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Изделие'),
                value: _selectedProductId,
                items: provider.products
                    .map((product) => DropdownMenuItem(
                        value: product.id, child: Text(product.name)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedProductId = value),
                validator: (value) => value == null ? 'Выберите изделие' : null,
              ),
              SizedBox(height: 16),
              Text('Дата изготовления:',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              InkWell(
                onTap: () => _pickDate(context),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat.yMd('ru_RU').format(_selectedDate),
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              SizedBox(height: 16),
              Text('Введите количество:',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Количество'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Введите количество';
                  final quantity = int.tryParse(value);
                  if (quantity == null || quantity <= 0)
                    return 'Количество должно быть больше 0';
                  return null;
                },
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate() &&
                      _selectedProductId != null) {
                    try {
                      final quantity = int.parse(_quantityController.text);
                      provider.addProductToInventory(
                          _selectedProductId!, quantity, _selectedDate);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Изделие добавлено в запасы')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: ${e.toString()}')),
                      );
                    }
                  }
                },
                child: Text('Добавить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- ЭКРАН ЗАКАЗОВ ---
class OrdersScreen extends StatefulWidget {
  final Function(DateTime?) onDaySelected;
  const OrdersScreen({required this.onDaySelected});

  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  DateTime _selectedDay = DateTime.now();
  OrderStatus? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onDaySelected(_selectedDay);
      }
    });
  }

  void _previousDay() {
    setState(() {
      _selectedDay = _selectedDay.subtract(Duration(days: 1));
      widget.onDaySelected(_selectedDay);
    });
  }

  void _nextDay() {
    setState(() {
      _selectedDay = _selectedDay.add(Duration(days: 1));
      widget.onDaySelected(_selectedDay);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      locale: Locale('ru', 'RU'),
    );
    if (picked != null) {
      setState(() {
        _selectedDay = picked;
        widget.onDaySelected(_selectedDay);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final List<Order> allOrders = List.from(provider.orders);
    List<Order> filteredOrders = List.from(allOrders);

    if (_selectedStatusFilter != null) {
      filteredOrders = filteredOrders
          .where((order) => order.status == _selectedStatusFilter)
          .toList();
    }

    filteredOrders = filteredOrders
        .where((order) => isSameDay(order.orderDate, _selectedDay))
        .toList();

    filteredOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          color: Theme.of(context).cardColor,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip(null, 'Все'),
                SizedBox(width: 8),
                _buildStatusChip(OrderStatus.inProgress, 'В работе'),
                SizedBox(width: 8),
                _buildStatusChip(OrderStatus.ready, 'Готов'),
                SizedBox(width: 8),
                _buildStatusChip(OrderStatus.completed, 'Выдан'),
              ],
            ),
          ),
        ),
        Divider(height: 1),
        Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          color: Colors.grey.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left),
                onPressed: _previousDay,
              ),
              InkWell(
                onTap: _pickDate,
                child: Row(
                  children: [
                    Icon(Icons.calendar_month,
                        size: 20, color: Theme.of(context).primaryColor),
                    SizedBox(width: 8),
                    Text(
                      DateFormat('d MMMM yyyy', 'ru_RU').format(_selectedDay),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right),
                onPressed: _nextDay,
              ),
            ],
          ),
        ),
        Divider(height: 1),
        Expanded(
          child: filteredOrders.isEmpty
              ? Center(
                  child: Text('Нет заказов на этот день',
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 80),
                  itemCount: filteredOrders.length,
                  itemBuilder: (context, index) {
                    final order = filteredOrders[index];
                    return OrderCard(order: order);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(OrderStatus? status, String label) {
    final isSelected = _selectedStatusFilter == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        setState(() {
          _selectedStatusFilter = selected ? status : null;
        });
      },
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      labelStyle: TextStyle(
          color: isSelected ? Theme.of(context).primaryColor : Colors.black),
    );
  }
}

bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// ===========================================================================
// ОБНОВЛЕННАЯ КАРТОЧКА ЗАКАЗА
// ===========================================================================
class OrderCard extends StatelessWidget {
  final Order order;
  const OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    final totalCost = order.getTotalCost();
    final totalPrice = order.getTotalPrice();
    final profit = order.getProfit();

    Color getStatusColor(OrderStatus status) {
      switch (status) {
        case OrderStatus.inProgress:
          return Colors.red;
        case OrderStatus.ready:
          return Colors.amber;
        case OrderStatus.completed:
          return Colors.green;
        default:
          return Colors.grey;
      }
    }

    String getStatusText(OrderStatus status) {
      switch (status) {
        case OrderStatus.inProgress:
          return 'В работе';
        case OrderStatus.ready:
          return 'Готов';
        case OrderStatus.completed:
          return 'Выдан';
        default:
          return 'Неизвестно';
      }
    }

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderEditScreen(initialOrder: order),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Кнопки статуса сверху
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _StatusButton(
                        icon: Icons.access_time,
                        isSelected: order.status == OrderStatus.inProgress,
                        color: Colors.red,
                        onTap: () => provider.updateOrderStatus(
                            order.id, OrderStatus.inProgress),
                      ),
                      _StatusButton(
                        icon: Icons.check_circle,
                        isSelected: order.status == OrderStatus.ready,
                        color: Colors.amber,
                        onTap: () =>
                            provider.updateOrderStatus(order.id, OrderStatus.ready),
                      ),
                      _StatusButton(
                        icon: Icons.done_all,
                        isSelected: order.status == OrderStatus.completed,
                        color: Colors.green,
                        onTap: () => provider.updateOrderStatus(
                            order.id, OrderStatus.completed),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red.shade400, size: 20),
                    onPressed: () => _confirmDelete(context, provider),
                  ),
                ],
              ),

              Divider(height: 12),

              // Компактная информация о клиенте
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (order.customerPhone != null &&
                      order.customerPhone!.isNotEmpty) ...[
                    Icon(Icons.phone, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(order.customerPhone!,
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ],
              ),

              SizedBox(height: 8),

              // Список изделий
              ...order.items.map((item) => Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.productName} x${item.quantity}',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          currencyFormat.format(item.getTotalPrice()),
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  )),

              // Украшения и упаковка (компактно)
              if (order.items
                  .any((i) => i.decorations.isNotEmpty || i.packaging.isNotEmpty))
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      ...order.items.expand((i) => i.decorations).map((d) => Chip(
                            label: Text(d.itemName, style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.pink.shade50,
                          )),
                      ...order.items.expand((i) => i.packaging).map((p) => Chip(
                            label: Text(p.itemName, style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.blue.shade50,
                          )),
                    ],
                  ),
                ),

              SizedBox(height: 8),

              // Итоговая строка
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MiniStat(
                        label: 'Цена', value: currencyFormat.format(totalPrice)),
                    _MiniStat(
                        label: 'С/с', value: currencyFormat.format(totalCost)),
                    _MiniStat(
                      label: 'Прибыль',
                      value: currencyFormat.format(profit),
                      color: profit >= 0 ? Colors.green : Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, PastryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить заказ?'),
        content: Text('Заказ для "${order.customerName}" будет удален'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('Отмена')),
          TextButton(
            onPressed: () {
              provider.deleteOrder(order.id);
              Navigator.pop(ctx);
            },
            child: Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _StatusButton({
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 22,
      color: isSelected ? color : Colors.grey.shade300,
      onPressed: onTap,
      padding: EdgeInsets.all(4),
      constraints: BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MiniStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }
}

// ===========================================================================
// ВСПОМОГАТЕЛЬНЫЙ КЛАСС ДЛЯ ФОРМЫ ИЗДЕЛИЯ
// ===========================================================================
class OrderItemFormData {
  String? id;
  String? selectedProductId;
  String? selectedInventoryItemId;
  String productName;
  double unitCostFromInventory;
  List<OrderDecorationPackagingItem> decorations;
  List<OrderDecorationPackagingItem> packaging;

  late TextEditingController priceController;
  late TextEditingController quantityController;

  OrderItemFormData({
    this.id,
    this.selectedProductId,
    this.selectedInventoryItemId,
    this.productName = '',
    this.unitCostFromInventory = 0,
    List<OrderDecorationPackagingItem>? decorations,
    List<OrderDecorationPackagingItem>? packaging,
    double? price,
    int? quantity,
  })  : decorations = decorations ?? [],
        packaging = packaging ?? [] {
    priceController = TextEditingController(text: price?.toString() ?? '');
    quantityController =
        TextEditingController(text: quantity?.toString() ?? '1');
  }

  factory OrderItemFormData.fromOrderItem(OrderItem item) {
    return OrderItemFormData(
      id: item.id,
      selectedProductId: item.productId,
      selectedInventoryItemId: item.inventoryItemId,
      productName: item.productName,
      unitCostFromInventory: item.unitCostFromInventory,
      decorations: List.from(item.decorations),
      packaging: List.from(item.packaging),
      price: item.sellingPrice,
      quantity: item.quantity,
    );
  }

  double get price => double.tryParse(priceController.text) ?? 0;
  int get quantity => int.tryParse(quantityController.text) ?? 1;

  String getTabName() {
    if (productName.isNotEmpty) {
      return productName.length > 15
          ? '${productName.substring(0, 15)}...'
          : productName;
    }
    return 'Новое изделие';
  }

  void dispose() {
    priceController.dispose();
    quantityController.dispose();
  }
}

// ===========================================================================
// ОБНОВЛЕННЫЙ ЭКРАН РЕДАКТИРОВАНИЯ ЗАКАЗА
// ===========================================================================
class OrderEditScreen extends StatefulWidget {
  final DateTime? selectedDate;
  final Order? initialOrder;
  const OrderEditScreen({this.selectedDate, this.initialOrder});

  @override
  _OrderEditScreenState createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _customerNameController;
  late TextEditingController _customerPhoneController;
  final MaskTextInputFormatter _phoneMaskFormatter = MaskTextInputFormatter(
    mask: '+7 (###) ###-##-##',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  List<OrderItemFormData> _orderItems = [];
  late TabController _tabController;

  bool get _isEditing => widget.initialOrder != null;
  final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(
      text: widget.initialOrder?.customerName ?? '',
    );
    _customerPhoneController = TextEditingController(
      text: widget.initialOrder?.customerPhone != null
          ? _phoneMaskFormatter.maskText(widget.initialOrder!.customerPhone!)
          : '',
    );

    if (_isEditing && widget.initialOrder!.items.isNotEmpty) {
      _orderItems = widget.initialOrder!.items
          .map((item) => OrderItemFormData.fromOrderItem(item))
          .toList();
    } else {
      _orderItems.add(OrderItemFormData());
    }

    _initTabController();
  }

  void _initTabController() {
    _tabController = TabController(
      length: _orderItems.length,
      vsync: this,
    );
  }

  void _addNewItem() {
    setState(() {
      _orderItems.add(OrderItemFormData());
      _tabController.dispose();
      _initTabController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tabController.animateTo(_orderItems.length - 1);
      });
    });
  }

  void _removeItem(int index) {
    if (_orderItems.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Нельзя удалить единственное изделие')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить изделие?'),
        content: Text(
            'Вы уверены, что хотите удалить "${_orderItems[index].getTabName()}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _orderItems[index].dispose();
                _orderItems.removeAt(index);
                _tabController.dispose();
                _initTabController();
              });
            },
            child: Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _tabController.dispose();
    for (var item in _orderItems) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактировать заказ' : 'Новый заказ'),
        actions: [
          TextButton.icon(
            onPressed: _addNewItem,
            icon: Icon(Icons.add, color: Colors.white),
            label: Text('Изделие', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildCustomerInfoSection(),
            Divider(height: 1),
            _buildItemsTabs(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _orderItems.asMap().entries.map((entry) {
                  return _buildItemForm(entry.key, entry.value, provider);
                }).toList(),
              ),
            ),
            _buildBottomSection(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfoSection() {
    return Container(
      padding: EdgeInsets.all(12),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _customerNameController,
                  decoration: InputDecoration(
                    labelText: 'Имя клиента',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                    prefixIcon: Icon(Icons.person, size: 20),
                  ),
                  style: TextStyle(fontSize: 14),
                  validator: (v) => v!.isEmpty ? 'Введите имя' : null,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _customerPhoneController,
                  decoration: InputDecoration(
                    labelText: 'Телефон',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                    prefixIcon: Icon(Icons.phone, size: 20),
                  ),
                  style: TextStyle(fontSize: 14),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_phoneMaskFormatter],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              SizedBox(width: 8),
              Text(
                'Дата: ${DateFormat('d MMMM yyyy', 'ru_RU').format(widget.selectedDate ?? widget.initialOrder?.orderDate ?? DateTime.now())}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsTabs() {
    return Container(
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Row( // 1. Оборачиваем в строку
        children: [
          Expanded( // 2. TabBar занимает всё доступное место
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: _orderItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.getTabName()),
                      if (_orderItems.length > 1)
                        Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: InkWell(
                            onTap: () => _removeItem(index),
                            child: Icon(Icons.close, size: 16, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          // 3. Добавляем кнопку ПЛЮС справа от вкладок
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Colors.grey.shade300))
            ),
            child: IconButton(
              icon: Icon(Icons.add, color: Theme.of(context).primaryColor),
              tooltip: 'Добавить еще изделие',
              onPressed: _addNewItem, // Вызываем тот же метод добавления
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildItemForm(
      int index, OrderItemFormData itemData, PastryProvider provider) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductSelectionRow(itemData, provider),
          SizedBox(height: 12),
          _buildPriceQuantityRow(itemData, provider),
          SizedBox(height: 12),
          _buildDecorationsSection(itemData, provider),
          SizedBox(height: 8),
          _buildPackagingSection(itemData, provider),
          SizedBox(height: 12),
          _buildItemSummary(itemData, provider),
        ],
      ),
    );
  }

  Widget _buildProductSelectionRow(
      OrderItemFormData itemData, PastryProvider provider) {
    
    // 1. Проверяем, существует ли выбранный ID в реальном списке продуктов
    // Если такого ID нет в списке provider.products, сбрасываем выбор в null, чтобы избежать краша
    if (itemData.selectedProductId != null) {
       final exists = provider.products.any((p) => p.id == itemData.selectedProductId);
       if (!exists) {
         itemData.selectedProductId = null;
         itemData.productName = '';
       }
    }

    List<InventoryItem> availableInventory = [];
    if (itemData.selectedProductId != null) {
      availableInventory =
          provider.getAvailableInventoryForProduct(itemData.selectedProductId!);
    }

    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: itemData.selectedProductId,
          decoration: InputDecoration(
            labelText: 'Изделие',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          isExpanded: true,
          items: provider.products
              .map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (value) {
            setState(() {
              itemData.selectedProductId = value;
              itemData.selectedInventoryItemId = null;
              itemData.productName =
                  value != null ? provider.getProductById(value).name : '';
            });
          },
          validator: (v) => v == null ? 'Выберите изделие' : null,
        ),
        SizedBox(height: 8),
        // Логика выбора партии (Inventory) остается прежней, но с защитой от null
        if (itemData.selectedProductId != null)
          DropdownButtonFormField<String?>(
            value: availableInventory.any((i) => i.id == itemData.selectedInventoryItemId) 
                ? itemData.selectedInventoryItemId 
                : null, // <--- ТАКАЯ ЖЕ ЗАЩИТА ДЛЯ ЗАПАСОВ
            decoration: InputDecoration(
              labelText: 'Партия из запасов',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            isExpanded: true,
            items: [
              DropdownMenuItem(value: null, child: Text('Готовить свежее (не из запасов)')),
              ...availableInventory.map((inv) => DropdownMenuItem(
                    value: inv.id,
                    child: Text(
                      '${inv.availableQuantity} шт - ${DateFormat.yMd('ru_RU').format(inv.productionDate)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: (value) {
              setState(() {
                itemData.selectedInventoryItemId = value;
                if (value != null) {
                  final inv =
                      provider.inventory.firstWhere((i) => i.id == value);
                  itemData.unitCostFromInventory =
                      inv.unitCostAtTimeOfProduction;
                } else {
                   itemData.unitCostFromInventory = 0; // Сброс себестоимости если выбрали "свежее"
                }
              });
            },
            // validator убираем или меняем, так как null здесь допустим (значит "под заказ")
          ),
      ],
    );
  }

  Widget _buildPriceQuantityRow(
      OrderItemFormData itemData, PastryProvider provider) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: itemData.priceController,
            decoration: InputDecoration(
              labelText: 'Цена, ₽',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            validator: (v) => v!.isEmpty ? 'Цена' : null,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: itemData.quantityController,
            decoration: InputDecoration(
              labelText: 'Кол-во',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            validator: (v) {
              if (v!.isEmpty) return 'Кол-во';
              final qty = int.tryParse(v);
              if (qty == null || qty <= 0) return '>0';
              if (itemData.selectedInventoryItemId != null) {
                final inv = provider.inventory.firstWhere(
                  (i) => i.id == itemData.selectedInventoryItemId,
                  orElse: () => InventoryItem(
                    id: '',
                    productId: '',
                    productName: '',
                    quantity: 0,
                    productionDate: DateTime.now(),
                    unitCostAtTimeOfProduction: 0,
                  ),
                );
                if (qty > inv.availableQuantity)
                  return 'Макс: ${inv.availableQuantity}';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDecorationsSection(
      OrderItemFormData itemData, PastryProvider provider) {
    return _buildAddonsSection(
      title: 'Украшения',
      items: itemData.decorations,
      onAdd: () =>
          _addAddon(itemData.decorations, IngredientType.decoration, provider),
      onRemove: (item) => setState(() => itemData.decorations.remove(item)),
      quantity: itemData.quantity,
    );
  }

  Widget _buildPackagingSection(
      OrderItemFormData itemData, PastryProvider provider) {
    return _buildAddonsSection(
      title: 'Упаковка',
      items: itemData.packaging,
      onAdd: () =>
          _addAddon(itemData.packaging, IngredientType.packaging, provider),
      onRemove: (item) => setState(() => itemData.packaging.remove(item)),
      quantity: itemData.quantity,
    );
  }

  Widget _buildAddonsSection({
    required String title,
    required List<OrderDecorationPackagingItem> items,
    required VoidCallback onAdd,
    required Function(OrderDecorationPackagingItem) onRemove,
    required int quantity,
  }) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              InkWell(
                onTap: onAdd,
                child: Row(
                  children: [
                    Icon(Icons.add,
                        size: 16, color: Theme.of(context).primaryColor),
                    Text('Добавить',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                        )),
                  ],
                ),
              ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Не добавлено',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            ...items.map((item) => Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.itemName} (${item.quantity.toStringAsFixed(0)})',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        currencyFormat
                            .format(item.itemPriceAtTime * item.quantity * quantity),
                        style: TextStyle(fontSize: 12),
                      ),
                      InkWell(
                        onTap: () => onRemove(item),
                        child: Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.close,
                              size: 14, color: Colors.red.shade300),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Future<void> _addAddon(
    List<OrderDecorationPackagingItem> list,
    IngredientType type,
    PastryProvider provider,
  ) async {
    final items = provider.getIngredientsByType(type);
    final result = await showDialog<OrderDecorationPackagingItem>(
      context: context,
      builder: (ctx) => AddDecorationPackagingDialog(
        title: type == IngredientType.decoration
            ? 'Добавить украшение'
            : 'Добавить упаковку',
        items: items,
      ),
    );
    if (result != null) {
      setState(() => list.add(result));
    }
  }

  Widget _buildItemSummary(OrderItemFormData itemData, PastryProvider provider) {
    final price = itemData.price;
    final quantity = itemData.quantity;
    final unitCost = itemData.unitCostFromInventory;

    double totalPrice = price * quantity;
    double totalCost = unitCost * quantity;

    for (var d in itemData.decorations) {
      totalCost += d.itemPriceAtTime * d.quantity * quantity;
    }
    for (var p in itemData.packaging) {
      totalCost += p.itemPriceAtTime * p.quantity * quantity;
    }

    final profit = totalPrice - totalCost;

    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMiniStat('Цена', currencyFormat.format(totalPrice)),
          _buildMiniStat('С/с', currencyFormat.format(totalCost)),
          _buildMiniStat(
            'Прибыль',
            currencyFormat.format(profit),
            color: profit >= 0 ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  Widget _buildBottomSection(PastryProvider provider) {
    double totalPrice = 0;
    double totalCost = 0;

    for (var item in _orderItems) {
      final qty = item.quantity;
      totalPrice += item.price * qty;
      totalCost += item.unitCostFromInventory * qty;
      for (var d in item.decorations) {
        totalCost += d.itemPriceAtTime * d.quantity * qty;
      }
      for (var p in item.packaging) {
        totalCost += p.itemPriceAtTime * p.quantity * qty;
      }
    }

    final profit = totalPrice - totalCost;

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTotalStat('Изделий', '${_orderItems.length}', Icons.cake),
                _buildTotalStat(
                    'Итого', currencyFormat.format(totalPrice), Icons.payments),
                _buildTotalStat(
                  'Прибыль',
                  currencyFormat.format(profit),
                  Icons.trending_up,
                  color: profit >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: _saveOrder,
                child: Text(
                  _isEditing ? 'Сохранить изменения' : 'Создать заказ',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalStat(String label, String value, IconData icon,
      {Color? color}) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey),
        SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  void _saveOrder() {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заполните все обязательные поля')),
      );
      return;
    }

    final provider = Provider.of<PastryProvider>(context, listen: false);

    for (var item in _orderItems) {
      if (item.selectedProductId == null ||
          item.selectedInventoryItemId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Выберите изделие и партию для всех позиций')),
        );
        return;
      }
    }

    final orderItems = _orderItems.map((formData) {
      return OrderItem(
        id: formData.id ?? Random().nextInt(100000).toString(),
        productId: formData.selectedProductId!,
        productName: formData.productName,
        inventoryItemId: formData.selectedInventoryItemId,
        unitCostFromInventory: formData.unitCostFromInventory,
        quantity: formData.quantity,
        sellingPrice: formData.price,
        decorations: List.from(formData.decorations),
        packaging: List.from(formData.packaging),
      );
    }).toList();

    final order = Order(
      id: _isEditing ? widget.initialOrder!.id : '',
      customerName: _customerNameController.text.trim(),
      customerPhone: _customerPhoneController.text.isEmpty
          ? null
          : _customerPhoneController.text,
      orderDate:
          widget.selectedDate ?? widget.initialOrder?.orderDate ?? DateTime.now(),
      status: _isEditing ? widget.initialOrder!.status : OrderStatus.inProgress,
      items: orderItems,
    );

    if (_isEditing) {
      provider.updateOrder(order);
    } else {
      provider.addOrder(order);
    }

    Navigator.pop(context);
  }
}

// --- ЭКРАН ИЗДЕЛИЙ ---
class ProductsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    return provider.products.isEmpty
        ? Center(
            child: Text(
                'У вас пока нет изделий.\nНажмите "+", чтобы добавить.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: provider.products.length,
            itemBuilder: (context, index) {
              final product = provider.products[index];
              final cost = product.getCost(provider.ingredients);
              final unitCost = product.getUnitCost(provider.ingredients);
              return Card(
                  elevation: 2,
                  margin: EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(product.name,
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Себестоимость (общая): ${cost.toStringAsFixed(2)} ₽'),
                        Text(
                            'Себестоимость (единица): ${unitCost.toStringAsFixed(2)} ₽'),
                        Text('Изготовлено: ${product.producedQuantity} шт'),
                      ],
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon:
                              Icon(Icons.inventory, color: Colors.blue.shade600),
                          tooltip: 'Добавить в запасы',
                          onPressed: () =>
                              _addToInventoryDialog(context, product, provider),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.grey.shade600),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      ProductEditScreen(initialProduct: product))),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red.shade400),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text('Подтвердите удаление'),
                                  content:
                                      Text('Удалить изделие "${product.name}"?'),
                                  actions: <Widget>[
                                    TextButton(
                                      child: Text('Отмена'),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                    TextButton(
                                      child: Text('Удалить'),
                                      onPressed: () {
                                        provider.deleteProduct(product.id);
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                'Изделие "${product.name}" удалено'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ));
            },
          );
  }

  void _addToInventoryDialog(
      BuildContext context, Product product, PastryProvider provider) {
    if (product.producedQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: Неверное количество изделия')));
      return;
    }

    DateTime selectedDate = DateTime.now();
    TextEditingController quantityController =
        TextEditingController(text: product.producedQuantity.toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Добавить в запасы'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Изделие: ${product.name}'),
                  SizedBox(height: 10),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Количество', border: OutlineInputBorder()),
                  ),
                  SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2101),
                        locale: Locale('ru', 'RU'),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Дата изготовления',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat.yMd('ru_RU').format(selectedDate)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Отмена')),
                ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(quantityController.text);
                    if (qty != null && qty > 0) {
                      try {
                        provider.addProductToInventory(
                            product.id, qty, selectedDate);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Добавлено в запасы: ${product.name} ($qty шт)')));
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка: ${e.toString()}')));
                      }
                    }
                  },
                  child: Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// --- ЭКРАН РЕДАКТИРОВАНИЯ ИЗДЕЛИЯ ---
class ProductEditScreen extends StatefulWidget {
  final Product? initialProduct;
  const ProductEditScreen({this.initialProduct});
  @override
  _ProductEditScreenState createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _producedQuantityController;
  late List<RecipeComponent> _ingredients;

  bool get _isEditing => widget.initialProduct != null;
  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialProduct?.name ?? '');
    _producedQuantityController = TextEditingController(
        text: widget.initialProduct?.producedQuantity.toString() ?? '1');
    _ingredients = widget.initialProduct?.ingredients
            .map((c) =>
                RecipeComponent(ingredientId: c.ingredientId, quantity: c.quantity))
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _producedQuantityController.dispose();
    super.dispose();
  }

  void _addComponent(List<RecipeComponent> componentList) async {
    final result = await showDialog<RecipeComponent>(
        context: context, builder: (context) => AddComponentDialog());
    if (result != null) {
      setState(() => componentList.add(result));
    }
  }

  void _removeComponent(
      List<RecipeComponent> componentList, RecipeComponent component) {
    setState(() {
      componentList.remove(component);
    });
  }

  Widget _buildComponentList(
      String title, List<RecipeComponent> components, PastryProvider provider) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        IconButton(
            icon: Icon(Icons.add_circle_outline,
                color: Theme.of(context).primaryColor),
            onPressed: () => _addComponent(components)),
      ]),
      if (components.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('  Компоненты не добавлены',
                style: TextStyle(color: Colors.grey))),
      ...components.asMap().entries.map((entry) {
        int idx = entry.key;
        RecipeComponent c = entry.value;
        final ingredient = provider
            .getIngredientsByType(IngredientType.ingredient)
            .firstWhere((ing) => ing.id == c.ingredientId,
                orElse: () => Ingredient(
                    id: 'not_found',
                    name: 'Не найден',
                    price: 0,
                    packageSize: 0,
                    type: IngredientType.ingredient));
        return ListTile(
          key: ValueKey('$title-$idx'),
          title: Text(ingredient.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${c.quantity.toStringAsFixed(0)} г/шт',
                  style: TextStyle(fontSize: 12)),
              IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => _removeComponent(components, c),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minHeight: 24, minWidth: 24)),
            ],
          ),
        );
      }).toList(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    int producedQuantity = int.tryParse(_producedQuantityController.text) ?? 1;
    double totalCost = Product(
            id: '',
            name: '',
            ingredients: _ingredients,
            producedQuantity: producedQuantity)
        .getCost(provider.ingredients);
    double unitCost = producedQuantity > 0 ? totalCost / producedQuantity : 0;

    return Scaffold(
      appBar:
          AppBar(title: Text(_isEditing ? 'Редактировать изделие' : 'Новое изделие')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                      labelText: 'Название изделия',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0)),
                  validator: (value) =>
                      value!.isEmpty ? 'Введите название' : null),
              SizedBox(height: 16),
              TextFormField(
                controller: _producedQuantityController,
                decoration: InputDecoration(
                    labelText: 'Количество изготовленных',
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value!.isEmpty) return 'Введите количество';
                  final quantity = int.tryParse(value);
                  if (quantity == null || quantity <= 0) {
                    return 'Количество должно быть больше 0';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),
              _buildComponentList('Ингредиенты', _ingredients, provider),
              Divider(height: 30),
              Text('Себестоимость (общая): ${totalCost.toStringAsFixed(2)} ₽',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text('Себестоимость (единица): ${unitCost.toStringAsFixed(2)} ₽',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16)),
                child: Text('Сохранить'),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final product = Product(
                        id: _isEditing ? widget.initialProduct!.id : '',
                        name: _nameController.text,
                        ingredients: _ingredients,
                        producedQuantity:
                            int.parse(_producedQuantityController.text));
                    if (_isEditing) {
                      provider.updateProduct(product);
                    } else {
                      provider.addProduct(product);
                    }
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- СПРАВОЧНИК ---
class IngredientsMainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            tabs: [
              Tab(text: 'Ингредиенты'),
              Tab(text: 'Украшения'),
              Tab(text: 'Упаковка'),
            ],
          ),
          title: Text('Справочник'),
        ),
        body: TabBarView(
          children: [
            IngredientsListScreen(type: IngredientType.ingredient),
            IngredientsListScreen(type: IngredientType.decoration),
            IngredientsListScreen(type: IngredientType.packaging),
          ],
        ),
      ),
    );
  }
}

class IngredientsListScreen extends StatelessWidget {
  final IngredientType type;
  const IngredientsListScreen({required this.type});
  String _getTypeName(IngredientType type) {
    switch (type) {
      case IngredientType.ingredient:
        return 'Ингредиенты';
      case IngredientType.decoration:
        return 'Украшения';
      case IngredientType.packaging:
        return 'Упаковка';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final ingredients = provider.getIngredientsByType(type);

    return ingredients.isEmpty
        ? Center(
            child: Text(
                '${_getTypeName(type)} пусты.\nНажмите "+", чтобы добавить.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: ingredients.length,
            itemBuilder: (context, index) {
              final ing = ingredients[index];
              return Card(
                  elevation: 2,
                  margin: EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(ing.name),
                    subtitle: Text(
                        '${ing.price} ₽ / ${ing.packageSize.toStringAsFixed(0)} г/шт'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.grey.shade600),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => IngredientEditScreen(
                                      initialIngredient: ing, type: ing.type))),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red.shade400),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text('Подтвердите удаление'),
                                  content: Text('Удалить "${ing.name}"?'),
                                  actions: <Widget>[
                                    TextButton(
                                      child: Text('Отмена'),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                    TextButton(
                                      child: Text('Удалить'),
                                      onPressed: () {
                                        provider.deleteIngredient(ing.id);
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ));
            },
          );
  }
}

class IngredientEditScreen extends StatefulWidget {
  final Ingredient? initialIngredient;
  final IngredientType type;
  const IngredientEditScreen({this.initialIngredient, required this.type});

  @override
  _IngredientEditScreenState createState() => _IngredientEditScreenState();
}

class _IngredientEditScreenState extends State<IngredientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _packageSizeController;
  late IngredientType _ingredientType;

  bool get _isEditing => widget.initialIngredient != null;
  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialIngredient?.name ?? '');
    _priceController = TextEditingController(
        text: widget.initialIngredient?.price.toString() ?? '');
    _packageSizeController = TextEditingController(
        text: widget.initialIngredient?.packageSize.toString() ?? '');
    _ingredientType = widget.initialIngredient?.type ?? widget.type;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _packageSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать' : 'Новый')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                      labelText: 'Название', border: OutlineInputBorder()),
                  validator: (value) =>
                      value!.isEmpty ? 'Введите название' : null),
              SizedBox(height: 16),
              TextFormField(
                  controller: _priceController,
                  decoration: InputDecoration(
                      labelText: 'Цена за упаковку, ₽',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) => value!.isEmpty ? 'Введите цену' : null),
              SizedBox(height: 16),
              TextFormField(
                  controller: _packageSizeController,
                  decoration: InputDecoration(
                      labelText: 'Вес/кол-во в упаковке (г/шт)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) => value!.isEmpty ? 'Введите вес' : null),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16)),
                child: Text('Сохранить'),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final ingredient = Ingredient(
                        id: _isEditing ? widget.initialIngredient!.id : '',
                        name: _nameController.text,
                        price: double.tryParse(_priceController.text) ?? 0,
                        packageSize:
                            double.tryParse(_packageSizeController.text) ?? 0,
                        type: _ingredientType);
                    final provider =
                        Provider.of<PastryProvider>(context, listen: false);
                    if (_isEditing) {
                      provider.updateIngredient(ingredient);
                    } else {
                      provider.addIngredient(ingredient);
                    }
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- ЭКРАН ЗАПАСОВ ---
class InventoryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    final availableInventory =
        provider.inventory.where((item) => item.availableQuantity > 0).toList();
    return availableInventory.isEmpty
        ? Center(
            child: Text(
                'Запасы пусты.\nСоздайте изделие и добавьте его в запасы.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: availableInventory.length,
            itemBuilder: (context, index) {
              final item = availableInventory[index];
              return Card(
                elevation: 2,
                margin: EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(item.productName,
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Количество: ${item.quantity} шт'),
                      Text('Доступно: ${item.availableQuantity} шт'),
                      Text(
                          'Дата изготовления: ${DateFormat.yMd('ru_RU').format(item.productionDate)}'),
                      Text(
                          'Себестоимость единицы: ${currencyFormat.format(item.unitCostAtTimeOfProduction)}'),
                    ],
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red.shade400),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text('Подтвердите удаление'),
                                content: Text(
                                    'Удалить запись о запасе "${item.productName}"?'),
                                actions: <Widget>[
                                  TextButton(
                                    child: Text('Отмена'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  TextButton(
                                    child: Text('Удалить'),
                                    onPressed: () {
                                      provider.deleteInventoryItem(item.id);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }
}

// --- СТАТИСТИКА ---
class StatisticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfYear = DateTime(now.year, 1, 1);
    final statsWeek = provider.getStatisticsForPeriod(startOfWeek, now);
    final statsMonth = provider.getStatisticsForPeriod(startOfMonth, now);
    final statsYear = provider.getStatisticsForPeriod(startOfYear, now);
    final statsAllTime = provider.getStatistics();

    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Неделя'),
              Tab(text: 'Месяц'),
              Tab(text: 'Год'),
              Tab(text: 'Всё время'),
            ],
          ),
          title: Text('Статистика'),
        ),
        body: TabBarView(
          children: [
            _buildStatsTabContent(context, statsWeek, currencyFormat, 'за неделю'),
            _buildStatsTabContent(
                context, statsMonth, currencyFormat, 'за месяц'),
            _buildStatsTabContent(context, statsYear, currencyFormat, 'за год'),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Статистика (выполненные заказы)',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center),
                      SizedBox(height: 24),
                      StatisticCard(
                          title: 'Полученная прибыль',
                          value:
                              currencyFormat.format(statsAllTime['profit'] ?? 0),
                          color: Colors.green),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Общая выручка',
                          value:
                              currencyFormat.format(statsAllTime['revenue'] ?? 0),
                          color: Colors.blue),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Общие затраты',
                          value: currencyFormat.format(statsAllTime['cost'] ?? 0),
                          color: Colors.orange),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Выполнено заказов',
                          value:
                              (statsAllTime['orderCount'] ?? 0).toInt().toString(),
                          color: Colors.grey),
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTabContent(BuildContext context, Map<String, double> stats,
      NumberFormat currencyFormat, String periodLabel) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Статистика $periodLabel',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            SizedBox(height: 24),
            StatisticCard(
              title: 'Прибыль',
              value: currencyFormat.format(stats['profit'] ?? 0),
              color: Colors.green,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Выручка',
              value: currencyFormat.format(stats['revenue'] ?? 0),
              color: Colors.blue,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Затраты',
              value: currencyFormat.format(stats['cost'] ?? 0),
              color: Colors.orange,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Количество заказов',
              value: (stats['orderCount'] ?? 0).toInt().toString(),
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Уникальных клиентов',
              value: (stats['customerCount'] ?? 0).toInt().toString(),
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }
}

class StatisticCard extends StatelessWidget {
  final String title, value;
  final Color color;
  const StatisticCard(
      {required this.title, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Card(
      elevation: 2,
      child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            Text(title, style: TextStyle(fontSize: 16, color: Colors.black54)),
            SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          ])));
}

class AddComponentDialog extends StatefulWidget {
  @override
  _AddComponentDialogState createState() => _AddComponentDialogState();
}

class _AddComponentDialogState extends State<AddComponentDialog> {
  String? _selectedIngredientId;
  final _quantityController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final ingredients =
        provider.getIngredientsByType(IngredientType.ingredient);
    return AlertDialog(
      title: Text('Добавить ингредиент'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          value: _selectedIngredientId,
          hint: Text('Выберите ингредиент'),
          items: ingredients
              .map(
                  (ing) => DropdownMenuItem(value: ing.id, child: Text(ing.name)))
              .toList(),
          onChanged: (value) => setState(() => _selectedIngredientId = value),
        ),
        SizedBox(height: 8),
        TextField(
            controller: _quantityController,
            decoration: InputDecoration(labelText: 'Количество (г/шт)'),
            keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text('Отмена')),
        ElevatedButton(
            onPressed: () {
              if (_selectedIngredientId != null &&
                  _quantityController.text.isNotEmpty) {
                final component = RecipeComponent(
                    ingredientId: _selectedIngredientId!,
                    quantity: double.tryParse(_quantityController.text) ?? 0);
                Navigator.pop(context, component);
              }
            },
            child: Text('Добавить')),
      ],
    );
  }
}

class AddDecorationPackagingDialog extends StatefulWidget {
  final String title;
  final List<Ingredient> items;
  const AddDecorationPackagingDialog(
      {required this.title, required this.items});
  @override
  _AddDecorationPackagingDialogState createState() =>
      _AddDecorationPackagingDialogState();
}

class _AddDecorationPackagingDialogState
extends State<AddDecorationPackagingDialog> {
String? _selectedItemId;
final _quantityController = TextEditingController(text: '1');
final _idGenerator = Random();
@override
Widget build(BuildContext context) {
return AlertDialog(
title: Text(widget.title),
content: Column(mainAxisSize: MainAxisSize.min, children: [
DropdownButtonFormField<String>(
initialValue: _selectedItemId,
hint: Text('Выберите элемент'),
items: widget.items
.map((item) =>
DropdownMenuItem(value: item.id, child: Text(item.name)))
.toList(),
onChanged: (value) => setState(() => _selectedItemId = value),
),
SizedBox(height: 8),
TextFormField(
controller: _quantityController,
decoration: InputDecoration(labelText: 'Количество (г/шт или шт)'),
keyboardType: TextInputType.number,
),
]),
actions: [
TextButton(
onPressed: () => Navigator.pop(context), child: Text('Отмена')),
ElevatedButton(
onPressed: () {
if (_selectedItemId != null &&
_quantityController.text.isNotEmpty) {
final selectedItem = widget.items
.firstWhere((item) => item.id == _selectedItemId);
final item = OrderDecorationPackagingItem(
id: _idGenerator.nextInt(100000).toString(),
itemId: _selectedItemId!,
quantity: double.tryParse(_quantityController.text) ?? 0,
itemName: selectedItem.name,
itemPriceAtTime: selectedItem.pricePerUnit,
);
Navigator.pop(context, item);
}
},
child: Text('Добавить')),
],
);
}
}