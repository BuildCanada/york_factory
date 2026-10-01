module PublicApi
  module V1
    # What a serializer needs to know about the request: the registry revision
    # that answers, the snapshot naming it (for cites), and the language of
    # `cite` and caveat text.
    Context = Data.define(:revision, :snapshot, :locale) do
      def fr? = locale == "fr"

      def pin(path) = Links.url(path, { "as_of" => revision })

      def dictionary = Catalog.dictionary(revision)

      # "revision 31 (snapshot release-14)", for cites.
      def version_label
        label = fr? ? "révision #{revision}" : "revision #{revision}"
        snapshot ? "#{label} (snapshot #{snapshot})" : label
      end
    end
  end
end
