module PublicApi
  module V1
    # What a serializer needs to know about the request: the release that
    # answers, the language of `cite` and caveat text, and whether person
    # entities may be shown (read:persons).
    Context = Data.define(:release, :locale, :persons) do
      def fr? = locale == "fr"

      def pin(path) = Links.url(path, { "as_of" => release })

      # The data dictionary the release was built with.
      def dictionary = Catalog.dictionary(release)
    end
  end
end
