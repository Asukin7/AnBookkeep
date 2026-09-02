import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

enum CategoryIconGroup {
  dining('餐饮'),
  transport('交通'),
  shopping('购物'),
  life('生活'),
  digital('数码'),
  entertainment('娱乐'),
  health('健康'),
  education('学习'),
  work('工作'),
  finance('理财'),
  reward('奖励'),
  other('其他');

  const CategoryIconGroup(this.label);

  final String label;
}

@immutable
class CategoryIconOption {
  const CategoryIconOption(this.code, this.iconData, this.group);

  final String code;
  final IconData iconData;
  final CategoryIconGroup group;
}

/// Built-in category icons. Existing codes stay unchanged so historical
/// categories keep their original appearance.
const categoryIconOptions = <CategoryIconOption>[
  CategoryIconOption(
    'food',
    Icons.restaurant_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption(
    'local_dining',
    Icons.local_dining_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption(
    'fastfood',
    Icons.fastfood_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption(
    'local_cafe',
    Icons.local_cafe_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption(
    'local_bar',
    Icons.local_bar_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption('cake', Icons.cake_outlined, CategoryIconGroup.dining),
  CategoryIconOption(
    'local_pizza',
    Icons.local_pizza_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption(
    'icecream',
    Icons.icecream_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption(
    'restaurant_menu',
    Icons.restaurant_menu_outlined,
    CategoryIconGroup.dining,
  ),
  CategoryIconOption(
    'transport',
    Icons.directions_bus_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'travel',
    Icons.luggage_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'directions_car',
    Icons.directions_car_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'directions_subway',
    Icons.directions_subway_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'local_taxi',
    Icons.local_taxi_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'flight',
    Icons.flight_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'train',
    Icons.train_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'directions_bike',
    Icons.directions_bike_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'directions_walk',
    Icons.directions_walk_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'local_gas_station',
    Icons.local_gas_station_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'local_parking',
    Icons.local_parking_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'local_shipping',
    Icons.local_shipping_outlined,
    CategoryIconGroup.transport,
  ),
  CategoryIconOption(
    'shopping',
    Icons.shopping_bag_outlined,
    CategoryIconGroup.shopping,
  ),
  CategoryIconOption(
    'shopping_cart',
    Icons.shopping_cart_outlined,
    CategoryIconGroup.shopping,
  ),
  CategoryIconOption('store', Icons.store_outlined, CategoryIconGroup.shopping),
  CategoryIconOption(
    'local_mall',
    Icons.local_mall_outlined,
    CategoryIconGroup.shopping,
  ),
  CategoryIconOption(
    'local_grocery_store',
    Icons.local_grocery_store_outlined,
    CategoryIconGroup.shopping,
  ),
  CategoryIconOption(
    'checkroom',
    Icons.checkroom_outlined,
    CategoryIconGroup.shopping,
  ),
  CategoryIconOption('watch', Icons.watch_outlined, CategoryIconGroup.shopping),
  CategoryIconOption(
    'diamond',
    Icons.diamond_outlined,
    CategoryIconGroup.shopping,
  ),
  CategoryIconOption('housing', Icons.home_outlined, CategoryIconGroup.life),
  CategoryIconOption('pet', Icons.pets_outlined, CategoryIconGroup.life),
  CategoryIconOption(
    'local_laundry_service',
    Icons.local_laundry_service_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'cleaning_services',
    Icons.cleaning_services_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'plumbing',
    Icons.plumbing_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'electrical_services',
    Icons.electrical_services_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'handyman',
    Icons.handyman_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'child_care',
    Icons.child_care_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'apartment',
    Icons.apartment_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'agriculture',
    Icons.agriculture_outlined,
    CategoryIconGroup.life,
  ),
  CategoryIconOption(
    'communication',
    Icons.phone_android_outlined,
    CategoryIconGroup.digital,
  ),
  CategoryIconOption(
    'computer',
    Icons.computer_outlined,
    CategoryIconGroup.digital,
  ),
  CategoryIconOption('phone', Icons.phone_outlined, CategoryIconGroup.digital),
  CategoryIconOption('wifi', Icons.wifi_outlined, CategoryIconGroup.digital),
  CategoryIconOption(
    'entertainment',
    Icons.sports_esports_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'movie',
    Icons.movie_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'music_note',
    Icons.music_note_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'sports_soccer',
    Icons.sports_soccer_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'sports_basketball',
    Icons.sports_basketball_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'theater_comedy',
    Icons.theater_comedy_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'camera_alt',
    Icons.camera_alt_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'palette',
    Icons.palette_outlined,
    CategoryIconGroup.entertainment,
  ),
  CategoryIconOption(
    'medical',
    Icons.medical_services_outlined,
    CategoryIconGroup.health,
  ),
  CategoryIconOption(
    'local_hospital',
    Icons.local_hospital_outlined,
    CategoryIconGroup.health,
  ),
  CategoryIconOption(
    'local_pharmacy',
    Icons.local_pharmacy_outlined,
    CategoryIconGroup.health,
  ),
  CategoryIconOption(
    'fitness_center',
    Icons.fitness_center_outlined,
    CategoryIconGroup.health,
  ),
  CategoryIconOption('spa', Icons.spa_outlined, CategoryIconGroup.health),
  CategoryIconOption(
    'psychology',
    Icons.psychology_outlined,
    CategoryIconGroup.health,
  ),
  CategoryIconOption('face', Icons.face_outlined, CategoryIconGroup.health),
  CategoryIconOption(
    'content_cut',
    Icons.content_cut_outlined,
    CategoryIconGroup.health,
  ),
  CategoryIconOption(
    'education',
    Icons.school_outlined,
    CategoryIconGroup.education,
  ),
  CategoryIconOption(
    'library_books',
    Icons.library_books_outlined,
    CategoryIconGroup.education,
  ),
  CategoryIconOption(
    'language',
    Icons.language_outlined,
    CategoryIconGroup.education,
  ),
  CategoryIconOption(
    'science',
    Icons.science_outlined,
    CategoryIconGroup.education,
  ),
  CategoryIconOption(
    'calculate',
    Icons.calculate_outlined,
    CategoryIconGroup.education,
  ),
  CategoryIconOption(
    'brush',
    Icons.brush_outlined,
    CategoryIconGroup.education,
  ),
  CategoryIconOption('part_time', Icons.work_outline, CategoryIconGroup.work),
  CategoryIconOption(
    'business',
    Icons.business_outlined,
    CategoryIconGroup.work,
  ),
  CategoryIconOption(
    'business_center',
    Icons.business_center_outlined,
    CategoryIconGroup.work,
  ),
  CategoryIconOption(
    'engineering',
    Icons.engineering_outlined,
    CategoryIconGroup.work,
  ),
  CategoryIconOption(
    'design_services',
    Icons.design_services_outlined,
    CategoryIconGroup.work,
  ),
  CategoryIconOption(
    'construction',
    Icons.construction_outlined,
    CategoryIconGroup.work,
  ),
  CategoryIconOption(
    'schedule',
    Icons.schedule_outlined,
    CategoryIconGroup.work,
  ),
  CategoryIconOption(
    'salary',
    Icons.account_balance_wallet_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'investment',
    Icons.trending_up_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'reimbursement',
    Icons.receipt_long_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'refund',
    Icons.currency_exchange_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'account_balance',
    Icons.account_balance_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'savings',
    Icons.savings_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption('paid', Icons.paid_outlined, CategoryIconGroup.finance),
  CategoryIconOption(
    'wallet',
    Icons.wallet_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'credit_card',
    Icons.credit_card_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'money',
    Icons.attach_money_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption('undo', Icons.undo_outlined, CategoryIconGroup.finance),
  CategoryIconOption(
    'handshake',
    Icons.handshake_outlined,
    CategoryIconGroup.finance,
  ),
  CategoryIconOption(
    'gift',
    Icons.card_giftcard_outlined,
    CategoryIconGroup.reward,
  ),
  CategoryIconOption(
    'bonus',
    Icons.emoji_events_outlined,
    CategoryIconGroup.reward,
  ),
  CategoryIconOption(
    'red_packet',
    Icons.redeem_outlined,
    CategoryIconGroup.reward,
  ),
  CategoryIconOption('star', Icons.star_outlined, CategoryIconGroup.reward),
  CategoryIconOption('grade', Icons.grade_outlined, CategoryIconGroup.reward),
  CategoryIconOption(
    'loyalty',
    Icons.loyalty_outlined,
    CategoryIconGroup.reward,
  ),
  CategoryIconOption(
    'volunteer_activism',
    Icons.volunteer_activism_outlined,
    CategoryIconGroup.reward,
  ),
  CategoryIconOption(
    'celebration',
    Icons.celebration_outlined,
    CategoryIconGroup.reward,
  ),
  CategoryIconOption('other', Icons.category_outlined, CategoryIconGroup.other),
  CategoryIconOption(
    'flash_on',
    Icons.flash_on_outlined,
    CategoryIconGroup.other,
  ),
  CategoryIconOption(
    'smoking_rooms',
    Icons.smoking_rooms_outlined,
    CategoryIconGroup.other,
  ),
  CategoryIconOption(
    'favorite',
    Icons.favorite_outlined,
    CategoryIconGroup.other,
  ),
  CategoryIconOption('help', Icons.help_outlined, CategoryIconGroup.other),
];

final categoryIconCodes = List<String>.unmodifiable(
  categoryIconOptions.map((option) => option.code),
);

final _categoryIconOptionsByCode = <String, CategoryIconOption>{
  for (final option in categoryIconOptions) option.code: option,
};

CategoryIconOption? categoryIconOptionForCode(String code) =>
    _categoryIconOptionsByCode[code];

List<CategoryIconOption> categoryIconOptionsForGroup(CategoryIconGroup group) =>
    categoryIconOptions.where((option) => option.group == group).toList();

IconData categoryIconData(String code) =>
    categoryIconOptionForCode(code)?.iconData ?? Icons.category_outlined;

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    required this.code,
    required this.color,
    this.selected = false,
    this.size = AppSizes.categoryIconLarge,
    super.key,
  });

  final String code;
  final Color color;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.standard,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(
          selected ? AppAlpha.selectedFill : AppAlpha.quietFill,
        ),
        border: selected ? Border.all(color: color, width: 2) : null,
      ),
      child: Icon(categoryIconData(code), color: color, size: size * 0.5),
    );
  }
}
