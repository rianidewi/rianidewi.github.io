import java.sql.*;
import java.util.*;

public class ExportProjects {
    private static String jsonEscape(String value) {
        if (value == null) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '\\': sb.append("\\\\"); break;
                case '"': sb.append("\\\""); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 32) {
                        sb.append(String.format("\\u%04x", (int)c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb.toString();
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("Usage: ExportProjects <jdbcUrl> <user> <password>");
            System.exit(1);
        }
        String url = args[0];
        String user = args[1];
        String pass = args[2];

        Class.forName("org.postgresql.Driver");

        String sql = "SELECT id, slug, title, type, summary, tags, source_url, demo_url, preview_image, status, sort_order " +
                     "FROM public.admin_project " +
                     "ORDER BY type, sort_order NULLS LAST, id DESC";

        try (Connection conn = DriverManager.getConnection(url, user, pass);
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            StringBuilder out = new StringBuilder();
            out.append("[");
            boolean first = true;
            while (rs.next()) {
                if (!first) out.append(",");
                first = false;
                out.append("{");
                out.append("\"id\":").append(rs.getLong("id")).append(",");
                out.append("\"slug\":\"").append(jsonEscape(rs.getString("slug"))).append("\",");
                out.append("\"title\":\"").append(jsonEscape(rs.getString("title"))).append("\",");
                out.append("\"type\":\"").append(jsonEscape(rs.getString("type"))).append("\",");
                out.append("\"summary\":\"").append(jsonEscape(rs.getString("summary"))).append("\",");
                out.append("\"tags\":\"").append(jsonEscape(rs.getString("tags"))).append("\",");
                out.append("\"sourceUrl\":\"").append(jsonEscape(rs.getString("source_url"))).append("\",");
                out.append("\"demoUrl\":\"").append(jsonEscape(rs.getString("demo_url"))).append("\",");
                out.append("\"previewImage\":\"").append(jsonEscape(rs.getString("preview_image"))).append("\",");
                out.append("\"status\":\"").append(jsonEscape(rs.getString("status"))).append("\",");
                int sort = rs.getInt("sort_order");
                if (rs.wasNull()) {
                    out.append("\"sortOrder\":null");
                } else {
                    out.append("\"sortOrder\":").append(sort);
                }
                out.append("}");
            }
            out.append("]");
            System.out.print(out.toString());
        }
    }
}
