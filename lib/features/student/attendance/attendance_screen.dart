/// attendance/attendance_screen.dart
/// Student attendance widget — shown inside session detail.
/// Shows check-in / check-out buttons and the student's own attendance record.
library;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_theme.dart';
import '../models.dart';
import 'attendance_provider.dart';

class StudentAttendanceWidget extends StatelessWidget {
  final SessionModel session;
  const StudentAttendanceWidget({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final provider   = context.watch<StudentAttendanceProvider>();
    final inSession  = provider.isCheckedIn;

    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        inSession
            ? AppTheme.danger.withValues(alpha:0.06)
            : AppTheme.primary.withValues(alpha:0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color:(inSession?AppTheme.danger:AppTheme.primary).withValues(alpha:0.2)),
      ),
      child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Icon(Icons.fact_check_rounded,
              color:inSession?AppTheme.danger:AppTheme.primary,size:20),
          const SizedBox(width:8),
          Text('سجل الحضور',
              style:AppTheme.h3.copyWith(color:inSession?AppTheme.danger:AppTheme.primary)),
        ]),
        const SizedBox(height:12),
        // Record summary
        if(provider.activeRecord!=null)...[
          _RecordRow('وقت الدخول',_fmt(provider.activeRecord!.checkInAt),
              Icons.login_rounded,AppTheme.success),
          if(provider.activeRecord!.checkOutAt!=null)...[
            const SizedBox(height:6),
            _RecordRow('وقت الخروج',_fmt(provider.activeRecord!.checkOutAt),
                Icons.logout_rounded,AppTheme.danger),
          ],
          const SizedBox(height:12),
        ],
        // Action button
        GestureDetector(
          onTap:()=>_toggle(context,provider),
          child:Container(
            height:44,
            decoration:BoxDecoration(
              gradient:inSession
                  ? const LinearGradient(colors:[AppTheme.danger,Color(0xFFFF6B6B)])
                  : AppTheme.primaryGradient,
              borderRadius:BorderRadius.circular(22),
              boxShadow:inSession?[]:AppTheme.primaryShadow),
            child:provider.isLoading
                ? const Center(child:SizedBox(width:20,height:20,
                    child:CircularProgressIndicator(color:Colors.white,strokeWidth:2)))
                : Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                    Icon(inSession?Icons.logout_rounded:Icons.login_rounded,
                        color:Colors.white,size:18),
                    const SizedBox(width:8),
                    Text(inSession?'تسجيل المغادرة':'تسجيل الحضور',
                        style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,
                            fontSize:14,fontFamily:'Cairo'))])),
        ),
      ]),
    );
  }

  Future<void> _toggle(BuildContext ctx, StudentAttendanceProvider p) async {
    bool ok;
    if(p.isCheckedIn){ ok=await p.checkOut(session.id); }
    else             { ok=await p.checkIn(session.id);  }
    if(ctx.mounted){
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content:Text(ok?(p.isCheckedIn?'تم تسجيل مغادرتك':'تم تسجيل حضورك ✓'):'حدث خطأ',
            style:const TextStyle(fontFamily:'Cairo',color:Colors.white)),
        backgroundColor:ok?AppTheme.success:AppTheme.danger,
        behavior:SnackBarBehavior.floating,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))));
    }
  }

  String _fmt(String? iso){
    if(iso==null)return'—';
    try{final dt=DateTime.parse(iso).toLocal();
      return'${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';}
    catch(_){return iso;}
  }
}

class _RecordRow extends StatelessWidget {
  final String label,value; final IconData icon; final Color color;
  const _RecordRow(this.label,this.value,this.icon,this.color);
  @override Widget build(BuildContext ctx)=>Row(children:[
    Icon(icon,size:14,color:color),const SizedBox(width:6),
    Text('$label: ',style:AppTheme.caption),
    Text(value,style:AppTheme.caption.copyWith(color:AppTheme.textDark,fontWeight:FontWeight.w700))]);
}
